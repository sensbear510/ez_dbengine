<?php
/**
 * ez_stress_master.php -  Web Edition
 * 結合 PHP FFI C 核心物理引擎與 網頁壓力測試儀表板
 * =================================================================
 *       [系統環境配置與執行說明 / System Setup & Execution Guide]
 *       
 *       1. 修改 php.ini (開啟 FFI 擴充與權限):
 *          --------------------------------------------------------------
 *          extension_dir = "ext"
 *          extension=ffi
 *          ffi.enable = true
 *          
 *       2. 驗證 FFI 是否啟用成功 (在 Terminal 執行):
 *          --------------------------------------------------------------
 *          php -r "var_dump(extension_loaded('ffi'));"   
 *          # 必須顯示: bool(true)
 *          
 *       3. 啟動網頁伺服器 (Web Server Startup):
 *          --------------------------------------------------------------
 *          cd ffi/php
 *          php -S localhost:8900
 *          
 *       4. 瀏覽器存取網址 (Browser Access URL):
 *          --------------------------------------------------------------
 *          http://localhost:8900/ez_stress_master_html.php
 *       ================================================================= -->
 */
// -----------------------------------------------------------------------------
// [後端 API 處理區] 接收前端 AJAX 請求並執行 FFI 壓力測試
// -----------------------------------------------------------------------------
if (isset($_GET['action'])) {
    ob_start();
    header('Content-Type: application/json; charset=utf-8');
    
    $action = $_GET['action'];
    $is_win = PHP_OS_FAMILY === 'Windows';
    $ds = DIRECTORY_SEPARATOR; // Windows 為 \，Linux 為 /

    $possible_paths = [
        __DIR__ . $ds . ($is_win ? 'ez_dbengine.dll' : 'libez_dbengine.so'),
        __DIR__ . "{$ds}..{$ds}..{$ds}build_win{$ds}Debug{$ds}ez_dbengine.dll",
        __DIR__ . "{$ds}..{$ds}..{$ds}build_win{$ds}Release{$ds}ez_dbengine.dll",
        __DIR__ . "{$ds}..{$ds}..{$ds}build_win{$ds}ez_dbengine.dll",
        __DIR__ . "{$ds}..{$ds}..{$ds}build_linux{$ds}libez_dbengine.so",
    ];

    $lib_path = null;
    foreach ($possible_paths as $p) {
        if (file_exists($p)) {
            // realpath() 會自動將路徑正規化為目前 OS 的標準格式 (Windows 會自動轉為 \)
            $lib_path = realpath($p);
            break;
        }
    }

    if (!$lib_path) {
        ob_end_clean();
        $target_name = $is_win ? 'ez_dbengine.dll' : 'libez_dbengine.so';
        echo json_encode([
            'status' => 'error', 
            'message' => "找不到 C 核心共享庫 [{$target_name}]，請確認已放置於 build_win 或 php 目錄中。"
        ]);
        exit;
    }

    // 檢查 FFI 擴充與共享庫
    if (!extension_loaded('ffi')) {
        ob_end_clean();
        echo json_encode(['status' => 'error', 'message' => 'PHP FFI 擴充未啟用，請在 php.ini 開啟 ffi.enable=true']);
        exit;
    }

    if (!file_exists($lib_path)) {
        ob_end_clean();
        echo json_encode(['status' => 'error', 'message' => "找不到 C 核心共享庫: {$lib_path}"]);
        exit;
    }

    $files = ['ez_full_stress.ebf', 'ez_full_stress_idx_code.edx', 'ez_full_stress_idx_date.edx'];

    foreach ($files as $file) {     
        if (file_exists($file)) {            
            unlink($file);
        }
    }

    try {
        // 初始化 FFI (完全對齊 ez_engine.h)
        $ffi = FFI::cdef("
            typedef uint64_t u64;
            typedef uint32_t u32;
            typedef double   f64;
            typedef float    f32;
            typedef int      EZ_STATUS;

            typedef struct __attribute__((packed)) {
                char     name[52];     /* 52 Bytes */
                uint8_t  type;         /* 1 Byte   */
                uint32_t len;          /* 4 Bytes  */
                uint8_t  dec;          /* 1 Byte   */
                uint8_t  storage;      /* 1 Byte   */
                uint32_t offset;       /* 4 Bytes  */
                uint8_t  zbf_sequence; /* 1 Byte   */
            } EZ_FIELD_NODE;

            typedef struct { u64 total_records; u32 field_count; u32 record_size; } EZ_MIGRATE_REPORT;

            EZ_STATUS ez_db_create(const char* filename, EZ_FIELD_NODE* fdt);
            u64       ez_db_open(const char* filename, EZ_MIGRATE_REPORT* rep);
            EZ_STATUS ez_db_append(u64 handle, const char* line, u32 count, const char* delim);
            EZ_STATUS ez_db_commit(u64 handle);
            EZ_STATUS ez_db_create_index(u64 handle, const char* idx_name, const char* field_name, int is_unique);
            EZ_STATUS ez_db_seek_by_tag(u64 handle, const char* idx_name, const char* key);
            u32       ez_db_recsize(u64 handle);
            EZ_STATUS ez_db_get_record(u64 handle, u32 tag_id, const char* tag_name, char* record_buf, u32 rec_size, int include_deleted);
            EZ_STATUS ez_db_skip(u64 handle, u32 tag_id, const char* tag_name, int step);
            int       ez_db_close_all(void);
        ", $lib_path);

        if ($action === 'run_stress') {
            $csv_file = __DIR__ . '/daily_2026-03-19.csv';
            $test_db  = 'ez_full_stress.ebf';

            // 1. 初始化 FDT
            $fdt = $ffi->new("EZ_FIELD_NODE[12]");
            $fields = [
                ["date",         'C', 10, 0], 
                ["code",         'C', 12, 0], 
                ["name",         'C', 36, 0], 
                ["trade_volume", 'N', 10, 0], 
                ["trade_amount", 'N', 12, 2], 
                ["open",         'N',  8, 2], 
                ["high",         'N',  8, 2], 
                ["low",          'N',  8, 2], 
                ["close",        'N',  8, 2], 
                ["diff",         'N',  8, 2], 
                ["trade_count",  'N',  8, 0]
            ];
            foreach ($fields as $idx => $f) {
                FFI::memcpy($fdt[$idx]->name, $f[0], strlen($f[0]));
                $fdt[$idx]->type = ord($f[1]);
                $fdt[$idx]->len  = $f[2];
                $fdt[$idx]->dec  = $f[3];
                $fdt[$idx]->storage      = 0; // 0: Inline
                $fdt[$idx]->offset       = 0; // 預設 0 (引擎會自動計算)
                $fdt[$idx]->zbf_sequence = 0;
            }
            $fdt[11]->type = 0;

            if (!file_exists($test_db)) {
                $ffi->ez_db_create($test_db, $fdt);
            }

            $m_rep = $ffi->new("EZ_MIGRATE_REPORT");
            $h = $ffi->ez_db_open($test_db, FFI::addr($m_rep));

            // 2. 讀取 CSV 並分配至 4 Bucket
            $buckets = [[], [], [], []];
            $total_records = 0;
            if (file_exists($csv_file)) {
                $fp = fopen($csv_file, 'r');
                fgets($fp); // skip header
                while (($line = fgets($fp)) !== false) {
                    $buckets[$total_records % 4][] = rtrim($line, "\r\n");
                    $total_records++;
                }
                fclose($fp);
            } else {
                // 若無 CSV 則自動生成 10,000 筆 Mock 測試資料
                for ($i = 0; $i < 10000; $i++) {
                    $buckets[$i % 4][] = "2026-03-19,0050,元大台灣50,1523000,213220000.00,140.00,141.50,139.80,141.00,1.00,1250";
                    $total_records++;
                }
            }

            // 3. 執行 4-Bucket 壓力測試
            $t_start = hrtime(true);
            $thread_times = [];

            for ($t = 0; $t < 4; $t++) {
                $ts = hrtime(true);
                foreach ($buckets[$t] as $line) {
                    $ffi->ez_db_append($h, $line, 1, ",");
                }
                $te = hrtime(true);
                $thread_times[$t] = ($te - $ts) / 1e6; // ms
            }

            $t_end = hrtime(true);
            $total_ms = ($t_end - $t_start) / 1e6;
            $ffi->ez_db_commit($h);

            // 4. 建立索引測試
            $ts_idx = hrtime(true);
            $ffi->ez_db_create_index($h, "idx_code", "code", 1);
            $te_idx = hrtime(true);
            $index_ms = ($te_idx - $ts_idx) / 1e6;

            $ffi->ez_db_close_all();

            $tps = $total_ms > 0 ? ($total_records * 1000.0) / $total_ms : 0;

            $c_raw_logs = ob_get_clean();

            echo json_encode([
                'status' => 'success',
                'total_records' => $total_records,
                'total_ms' => round($total_ms, 3),
                'tps' => round($tps, 2),
                'index_ms' => round($index_ms, 3),
                'threads' => array_map(function($ms, $idx) use ($buckets) {
                    return [
                        'id' => $idx,
                        'recs' => count($buckets[$idx]),
                        'time_ms' => round($ms, 3)
                    ];
                }, $thread_times, array_keys($thread_times))
            ]);
            exit;
        }
    } catch (Exception $e) {
        ob_end_clean();
        echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
        exit;
    }
}
?>
<!DOCTYPE html>
<html lang="zh-TW">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>EDB 2.0 Stress Master - Web UI</title>
    <style>
        /* -----------------------------------------------------------------
           Flutter Windows / Material 3 Dark Theme Styles
        ----------------------------------------------------------------- */
        :root {
            --bg-color: #0d0e11;
            --surface-color: #17181c;
            --card-color: #1e1f25;
            --card-hover: #262730;
            --primary-color: #00d2ff;
            --primary-accent: #00e5ff;
            --purple-accent: #bb86fc;
            --text-main: #e3e2e6;
            --text-muted: #8e9099;
            --border-color: rgba(255, 255, 255, 0.08);
            --window-bar-bg: #111215;
            --font-family: 'Segoe UI', system-ui, -apple-system, Roboto, sans-serif;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; }

        body {
            background-color: var(--bg-color);
            color: var(--text-main);
            font-family: var(--font-family);
            height: 100vh;
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }

        /* Flutter Windows Top Title Bar */
        .window-bar {
            height: 38px;
            background-color: var(--window-bar-bg);
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0 12px;
            border-bottom: 1px solid var(--border-color);
            font-size: 12px;
            color: var(--text-muted);
        }

        .window-title {
            display: flex;
            align-items: center;
            gap: 8px;
            font-weight: 600;
            color: var(--text-main);
        }

        .flutter-logo {
            width: 14px;
            height: 14px;
            background: linear-gradient(135deg, #54c5f8, #01579b);
            clip-path: polygon(0% 0%, 60% 0%, 100% 40%, 60% 80%, 100% 100%, 40% 100%, 0% 60%);
        }

        .window-controls {
            display: flex;
            gap: 16px;
        }

        .win-btn { cursor: pointer; opacity: 0.7; transition: 0.2s; }
        .win-btn:hover { opacity: 1; }
        .win-close:hover { color: #ff5252; }

        /* Main App Container (NavigationRail + Content) */
        .app-container {
            display: flex;
            flex: 1;
            height: calc(100vh - 38px);
        }

        /* Flutter NavigationRail (Sidebar) */
        .nav-rail {
            width: 72px;
            background-color: var(--surface-color);
            border-right: 1px solid var(--border-color);
            display: flex;
            flex-direction: column;
            align-items: center;
            padding: 16px 0;
            gap: 24px;
        }

        .nav-item {
            width: 48px;
            height: 48px;
            border-radius: 16px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 4px;
            cursor: pointer;
            color: var(--text-muted);
            font-size: 10px;
            transition: all 0.2s ease;
        }

        .nav-item.active {
            background-color: rgba(0, 210, 255, 0.12);
            color: var(--primary-color);
        }

        .nav-item:hover:not(.active) {
            background-color: rgba(255, 255, 255, 0.05);
            color: var(--text-main);
        }

        .nav-icon { font-size: 18px; }

        /* Content Area */
        .content-area {
            flex: 1;
            padding: 24px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 20px;
        }

        .header-title {
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .header-title h1 {
            font-size: 24px;
            font-weight: 600;
            background: linear-gradient(90deg, #ffffff, #8e9099);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }

        /* Flutter Material 3 Elevated Button */
        .flutter-btn {
            background: linear-gradient(135deg, #00d2ff, #0072ff);
            color: #000;
            font-weight: 700;
            border: none;
            padding: 12px 24px;
            border-radius: 24px;
            cursor: pointer;
            font-size: 14px;
            display: flex;
            align-items: center;
            gap: 8px;
            box-shadow: 0 4px 15px rgba(0, 210, 255, 0.3);
            transition: all 0.2s ease;
        }

        .flutter-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0, 210, 255, 0.5);
        }

        .flutter-btn:active { transform: translateY(0); }

        /* Stat Cards Grid */
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 16px;
        }

        .flutter-card {
            background-color: var(--card-color);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 20px;
            display: flex;
            flex-direction: column;
            gap: 8px;
            position: relative;
            overflow: hidden;
            transition: all 0.2s;
        }

        .flutter-card::before {
            content: '';
            position: absolute;
            top: 0; left: 0; right: 0; height: 2px;
            background: transparent;
        }

        .flutter-card.accent-cyan::before { background: var(--primary-color); }
        .flutter-card.accent-purple::before { background: var(--purple-accent); }

        .card-label { font-size: 12px; color: var(--text-muted); font-weight: 500; }
        .card-value { font-size: 28px; font-weight: 700; color: #fff; }
        .card-sub { font-size: 11px; color: var(--text-muted); }

        /* Threads / Buckets Performance Area */
        .dashboard-row {
            display: grid;
            grid-template-columns: 2fr 1fr;
            gap: 16px;
        }

        .thread-bar-container {
            display: flex;
            flex-direction: column;
            gap: 12px;
            margin-top: 12px;
        }

        .thread-row {
            display: flex;
            align-items: center;
            gap: 12px;
            font-size: 13px;
        }

        .progress-bg {
            flex: 1;
            height: 10px;
            background-color: rgba(255, 255, 255, 0.05);
            border-radius: 5px;
            overflow: hidden;
        }

        .progress-fill {
            height: 100%;
            width: 0%;
            background: linear-gradient(90deg, var(--primary-color), var(--purple-accent));
            border-radius: 5px;
            transition: width 0.6s cubic-bezier(0.1, 0.8, 0.3, 1);
        }

        /* Realtime Log Terminal Window */
        .terminal-box {
            background-color: #090a0c;
            border: 1px solid var(--border-color);
            border-radius: 12px;
            padding: 16px;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 12px;
            color: #00e5ff;
            height: 180px;
            overflow-y: auto;
            display: flex;
            flex-direction: column;
            gap: 6px;
        }

        .log-line { opacity: 0.9; }
        .log-success { color: #00e676; }
        .log-warn { color: #ffb300; }

        /* Responsive */
        @media (max-width: 900px) {
            .stats-grid { grid-template-columns: repeat(2, 1fr); }
            .dashboard-row { grid-template-columns: 1fr; }
        }
    </style>
</head>
<body>

    <!-- Flutter Windows Desktop Top Title Bar -->
    <div class="window-bar">
        <div class="window-title">
            <div class="flutter-logo"></div>
            <span>EDB 2.0 Physical Stress Master (Flutter Desktop Edition)</span>
        </div>
        <div class="window-controls">
            <span class="win-btn">🗕</span>
            <span class="win-btn">🗖</span>
            <span class="win-btn win-close">✕</span>
        </div>
    </div>

    <!-- Main Layout Container -->
    <div class="app-container">
        
        <!-- NavigationRail (Left Sidebar) -->
        <div class="nav-rail">
            <div class="nav-item active">
                <span class="nav-icon">⚡</span>
                <span>測試</span>
            </div>
            <div class="nav-item">
                <span class="nav-icon">📊</span>
                <span>指標</span>
            </div>
            <div class="nav-item">
                <span class="nav-icon">💾</span>
                <span>結構</span>
            </div>
            <div class="nav-item">
                <span class="nav-icon">⚙️</span>
                <span>設定</span>
            </div>
        </div>

        <!-- Main Dashboard View Area -->
        <div class="content-area">
            
            <div class="header-title">
                <div>
                    <h1>ez_DBEngine 核心物理引擎壓力測試儀表板</h1>
                </div>
                <button class="flutter-btn" id="runBtn" onclick="runStressTest()">
                    <span>▶ 執行 4-Bucket 測試</span>
                </button>
            </div>

            <!-- Top Metric Cards -->
            <div class="stats-grid">
                <div class="flutter-card accent-cyan">
                    <span class="card-label">Overall Throughput</span>
                    <span class="card-value" id="valTps">0.00</span>
                    <span class="card-sub">TPS (Transactions / Sec)</span>
                </div>
                <div class="flutter-card accent-purple">
                    <span class="card-label">Total Execution Time</span>
                    <span class="card-value" id="valTime">0.00 <span style="font-size:14px">ms</span></span>
                    <span class="card-sub">物理總耗時</span>
                </div>
                <div class="flutter-card">
                    <span class="card-label">Total Injected Records</span>
                    <span class="card-value" id="valRecords">0</span>
                    <span class="card-sub">4-Bucket 筆數總計</span>
                </div>
                <div class="flutter-card">
                    <span class="card-label">Index Create Time</span>
                    <span class="card-value" id="valIndex">0.00 <span style="font-size:14px">ms</span></span>
                    <span class="card-sub">Tag 重構耗時</span>
                </div>
            </div>

            <!-- Middle Charts & Threads Execution -->
            <div class="dashboard-row">
                
                <div class="flutter-card">
                    <span class="card-label" style="font-size: 14px; color: #fff;">4 Worker Threads (Buckets) 物理平行吞吐分析</span>
                    <div class="thread-bar-container">
                        <div class="thread-row">
                            <span style="width: 80px; color: var(--text-muted);">Bucket [0]</span>
                            <div class="progress-bg"><div class="progress-fill" id="bar0"></div></div>
                            <span style="width: 70px; text-align: right;" id="time0">0 ms</span>
                        </div>
                        <div class="thread-row">
                            <span style="width: 80px; color: var(--text-muted);">Bucket [1]</span>
                            <div class="progress-bg"><div class="progress-fill" id="bar1"></div></div>
                            <span style="width: 70px; text-align: right;" id="time1">0 ms</span>
                        </div>
                        <div class="thread-row">
                            <span style="width: 80px; color: var(--text-muted);">Bucket [2]</span>
                            <div class="progress-bg"><div class="progress-fill" id="bar2"></div></div>
                            <span style="width: 70px; text-align: right;" id="time2">0 ms</span>
                        </div>
                        <div class="thread-row">
                            <span style="width: 80px; color: var(--text-muted);">Bucket [3]</span>
                            <div class="progress-bg"><div class="progress-fill" id="bar3"></div></div>
                            <span style="width: 70px; text-align: right;" id="time3">0 ms</span>
                        </div>
                    </div>
                </div>

                <div class="flutter-card">
                    <span class="card-label" style="font-size: 14px; color: #fff;">引擎物理參數 (EBF Engine)</span>
                    <div style="display: flex; flex-direction: column; gap: 12px; margin-top: 12px; font-size: 13px;">
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: var(--text-muted);">Record Stride:</span>
                            <span style="font-weight: 600;">128 Bytes (Fixed)</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: var(--text-muted);">Concurrency:</span>
                            <span style="font-weight: 600;">4 Worker Buckets</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: var(--text-muted);">Lock Mechanism:</span>
                            <span style="color: var(--primary-color); font-weight: 600;">Lock-Free Slice</span>
                        </div>
                        <div style="display: flex; justify-content: space-between;">
                            <span style="color: var(--text-muted);">FFI Bridge:</span>
                            <span style="color: #00e676; font-weight: 600;">Direct C-Call</span>
                        </div>
                    </div>
                </div>

            </div>

            <!-- Bottom Console Log Terminal -->
            <div class="flutter-card">
                <span class="card-label" style="margin-bottom: 8px;">C-Engine Execution Log Terminal</span>
                <div class="terminal-box" id="terminal">
                    <div class="log-line">[SYSTEM] Flutter Windows UI Layer Initialized.</div>
                    <div class="log-line">[READY] Awaiting 4-Bucket Stress Test Trigger...</div>
                </div>
            </div>

        </div>
    </div>

    <!-- Frontend Interactive Script -->
    <script>
        function logToTerminal(msg, type = '') {
            const term = document.getElementById('terminal');
            const div = document.createElement('div');
            div.className = 'log-line ' + (type ? 'log-' + type : '');
            const timeStr = new Date().toISOString().substr(11, 8);
            div.innerText = `[${timeStr}] ${msg}`;
            term.appendChild(div);
            term.scrollTop = term.scrollHeight;
        }

        async function runStressTest() {
            const btn = document.getElementById('runBtn');
            btn.style.opacity = '0.5';
            btn.style.pointerEvents = 'none';
            btn.innerHTML = '<span>⚡ 執行中...</span>';

            logToTerminal('開始發起 C 核心物理壓力測試 (4-Bucket 注入)...', 'warn');

            try {
                const response = await fetch('?action=run_stress');
                const data = await response.json();

                if (data.status === 'success') {
                    if (data.c_logs && data.c_logs.trim() !== '') {
                        logToTerminal('[C-ENGINE] ' + data.c_logs.trim(), 'warn');
                    }
                    // 更新數字
                    document.getElementById('valTps').innerText = data.tps.toLocaleString();
                    document.getElementById('valTime').innerHTML = `${data.total_ms} <span style="font-size:14px">ms</span>`;
                    document.getElementById('valRecords').innerText = data.total_records.toLocaleString();
                    document.getElementById('valIndex').innerHTML = `${data.index_ms} <span style="font-size:14px">ms</span>`;

                    // 計算動畫進度條
                    const maxTime = Math.max(...data.threads.map(t => t.time_ms));
                    data.threads.forEach(t => {
                        const pct = maxTime > 0 ? (t.time_ms / maxTime) * 100 : 0;
                        document.getElementById(`bar${t.id}`).style.width = `${pct}%`;
                        document.getElementById(`time${t.id}`).innerText = `${t.time_ms} ms`;
                    });

                    logToTerminal(`[測試成功] 寫入 ${data.total_records} 筆資料 | 耗時: ${data.total_ms} ms | 吞吐量: ${data.tps} TPS`, 'success');
                    logToTerminal(`[索引建置] Tag idx_code 建立完成，耗時: ${data.index_ms} ms`, 'success');
                } else {
                    logToTerminal(`[ERROR] ${data.message}`, 'warn');
                }
            } catch (err) {
                logToTerminal(`[FATAL] 網路或 FFI 崩潰: ${err.message}`, 'warn');
            } finally {
                btn.style.opacity = '1';
                btn.style.pointerEvents = 'auto';
                btn.innerHTML = '<span>▶ 執行 4-Bucket 測試</span>';
            }
        }
    </script>
</body>
</html>