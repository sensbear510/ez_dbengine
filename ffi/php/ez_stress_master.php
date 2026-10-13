<?php
/**
 * ez_stress_master.php - EDB 2.0 CLI Physical Stress Test & Benchmarking Script
 * 
 * =================================================================
 * [非網頁 CLI 版本環境配置與執行說明 / CLI Execution Guide]
 * 
 * 1. 修改 php.ini (開啟 FFI 擴充與權限):
 *    --------------------------------------------------------------
 *    extension_dir = "ext"
 *    extension=ffi
 *    ffi.enable = true
 * 
 * 2. 驗證 FFI 是否啟用成功 (在 Terminal 執行):
 *    --------------------------------------------------------------
 *    php -r "var_dump(extension_loaded('ffi'));"   
 *    # 必須顯示: bool(true)
 * 
 * 3. CLI 執行方式 (Command Line Execution):
 *    --------------------------------------------------------------
 *    cd ffi/php
 *    php ez_stress_master.php
 * =================================================================
 */

require_once __DIR__ . '/ez_dbengine.php';

use EzDB\EzDBEngine;
use EzDB\Field;

const TEST_DB = 'ez_full_stress.ebf';
const CSV_FILE = __DIR__ . '/daily_2026-03-19.csv';
const NUM_THREADS = 4;

function get_tick(): float {
    return hrtime(true) / 1e6;
}

/**
 * 徹底動態清除當前目錄下所有的 .ebf 與 .edx 殘留檔案
 */
function clean_old_files(): void {
    $dir = __DIR__;
    $files = scandir($dir);
    if ($files !== false) {
        foreach ($files as $f) {
            $ext = strtolower(pathinfo($f, PATHINFO_EXTENSION));
            if ($ext === 'ebf' || $ext === 'edx') {
                $target = $dir . DIRECTORY_SEPARATOR . $f;
                if (is_file($target)) {
                    @unlink($target);
                    echo "[CLEAN] 已清除殘留資料庫檔案: {$f}\n";
                }
            }
        }
    }
}

clean_old_files();

$tStart = get_tick();
echo "=== EDB 2.0 Physical Stress Test (PHP CLI Aligned Edition) ===\n";

// 1. 定義 Schema (長度與型別精確對齊)
$schema = [
    new Field("date",         'C', 10, 0),
    new Field("code",         'C', 12, 0),
    new Field("name",         'C', 36, 0),
    new Field("trade_volume", 'N', 10, 0),
    new Field("trade_amount", 'N', 12, 2),
    new Field("open",         'N',  8, 2),
    new Field("high",         'N',  8, 2),
    new Field("low",          'N',  8, 2),
    new Field("close",        'N',  8, 2),
    new Field("diff",         'N',  8, 2),
    new Field("trade_count",  'N',  8, 0)
];

// 2. 建立資料庫
if (!file_exists(TEST_DB)) {
    $createSt = EzDBEngine::create(TEST_DB, $schema);
    if ($createSt !== 0) {
        fwrite(STDERR, "[ERROR] EzDBEngine::create 失敗: " . EzDBEngine::getDetailedError($createSt) . "\n");
        exit(1);
    }
}

// 3. 掛載資料庫
$db = new EzDBEngine(TEST_DB);
$db->debugDumpWorkArea();

// 4. 解析 CSV 並分配 Buckets
$buckets = array_fill(0, NUM_THREADS, []);
$totalRecords = 0;

if (file_exists(CSV_FILE)) {
    $fp = fopen(CSV_FILE, 'r');
    fgets($fp); // 跳過標頭
    while (($line = fgets($fp)) !== false) {
        $buckets[$totalRecords % NUM_THREADS][] = rtrim($line, "\r\n");
        $totalRecords++;
    }
    fclose($fp);
} else {
    echo "[WARNING] CSV file not found, generating 10,000 mock records...\n";
    for ($i = 0; $i < 10000; $i++) {
        $buckets[$i % NUM_THREADS][] = "2026-03-19,0050,元大台灣50,1523000,213220000.00,140.00,141.50,139.80,141.00,1.00,1250";
        $totalRecords++;
    }
}

for ($i = 0; $i < NUM_THREADS; $i++) {
    printf("  ├─► Bucket [%d] loaded with %d records\n", $i, count($buckets[$i]));
}

// 5. 執行 4-Bucket 寫入壓測
// 5. 執行 4-Bucket 寫入壓測
echo "\n=== [4-Bucket Stress] Executing append_record ===\n";
$stressStart = get_tick();
$workerTimes = [];

for ($t = 0; $t < NUM_THREADS; $t++) {
    $ts = get_tick();
    foreach ($buckets[$t] as $line) {
        // 直接傳入標準字串 ","，底層 ez_dbengine.php 已處理 uint8_t* 轉型
        $st = $db->append($line, 1, ",");
        if ($st !== 0) {
            fwrite(STDERR, "[Worker {$t} Error] " . EzDBEngine::getDetailedError($st) . "\n");
        }
    }
    $workerTimes[$t] = get_tick() - $ts;
}

$commitSt = $db->commit();
if ($commitSt !== 0) {
    echo "[WARN] commit 回傳非零狀態: " . EzDBEngine::getDetailedError($commitSt) . "\n";
}

$totalMs = get_tick() - $stressStart;
$tps = $totalMs > 0 ? ($totalRecords * 1000.0) / $totalMs : 0;

echo "╔═══════════════════════════════════════════════════════════════════╗\n";
echo "║  [4-THREAD BUCKET STRESS REPORT - PHP NATIVE]                     ║\n";
echo "╠═══════════════════════════════════════════════════════════════════╣\n";
for ($i = 0; $i < NUM_THREADS; $i++) {
    printf("  │ Thread [%d] Execution Time: %8.3f ms (%d recs)\n", $i, $workerTimes[$i], count($buckets[$i]));
}
echo "  ├─────────────────────────────────────────────────────────────────┤\n";
printf("  │ Total Injected Records : %u\n", $totalRecords);
printf("  │ Total Elapsed Time     : %8.3f ms\n", $totalMs);
printf("  │ Overall Throughput     : %8.2f TPS\n", $tps);
echo "╚═══════════════════════════════════════════════════════════════════╝\n";

// 6. 建立索引
$idxStart = get_tick();
$idxSt = $db->createIndex("idx_code", "code", true);
$idxTime = get_tick() - $idxStart;
printf("<<< createIndex | Status: %d | Tag: idx_code | Time: %8.3f ms\n", $idxSt, $idxTime);
if ($idxSt !== 0) {
    fwrite(STDERR, "[ERROR] createIndex 失敗: " . EzDBEngine::getDetailedError($idxSt) . "\n");
}

// 7. 循序讀取測試 (以 2330 為目標檢索)
echo "=== 執行 seekByTag 搜尋 '2330' ===\n";
if ($db->seekByTag("idx_code", "2330")) {
    $count = 0;
    while ($rawBuf = $db->getRecord(0, 0, "idx_code")) {
        $code = rtrim(substr($rawBuf, 10, 12), "\0 ");
        if (!str_starts_with($code, "2330")) break;
        $count++;
        if ($db->skip(1, 0, 0, "idx_code") !== 0) break;
    }
    printf(">>> 2330 Rolling Read Count: %d\n", $count);
} else {
    echo "[INFO] 搜尋 2330 未找到符合的紀錄\n";
}

$db->close();
$tEnd = get_tick();
printf("\nTotal Performance: %8.3f ms\n", $tEnd - $tStart);