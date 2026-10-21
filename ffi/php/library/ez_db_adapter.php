<?php
require_once(EZ_SDK_PATH);
use EzDB\EzDBEngine;

class EzDbAdapter {
    private static $_instance = null;
    private $engine = null;
    private $handles = [];   // Table Path => Handle 快取池

    private function __construct() {
        // 核心單例：伺服器生命週期內只產生一個常駐實體
        $this->engine = method_exists('EzDB\EzDBEngine', 'getInstance') 
            ? EzDBEngine::getInstance() 
            : new EzDBEngine();
    }

    public static function getInstance() {
        if (self::$_instance === null) {
            self::$_instance = new self();
        }
        return self::$_instance;
    }

    // 掛載或取得已開啟的 EBF Handle
    public function getHandle($tableName) {
        $filePath = DIR_DATA . EBF_TABLE_PREFIX . $tableName . '.ebf';
        if (!isset($this->handles[$filePath])) {
            $h = $this->engine->use($filePath);
            if ($h <= 0) {
                throw new Exception("Failed to mount EBF table: " . $filePath);
            }
            $this->handles[$filePath] = $h;
        }
        return $this->handles[$filePath];
    }

    // 透過 EDX 索引標籤精確查詢單筆 (取代 SELECT ... WHERE key = ... LIMIT 1)
    public function findOneByTag($tableName, $tagName, $keyValue) {
        $h = $this->getHandle($tableName);
        $found = $this->engine->seekByTag($tagName, (string)$keyValue, $h);
        if (!$found) return null;

        $recNo = $this->engine->getRecno(0, $h);
        return $this->readRecordMap($h, $recNo);
    }

    // 依實體 RowID 讀取完整欄位 Map
    public function readRecordMap($h, $recNo) {
        $this->engine->goTo($recNo, 0, $h);
        $raw = $this->engine->getRecord(0, $h);
        if ($raw === null) return null;

        $fields = $this->engine->getFdt($h);
        $row = ['__recno' => $recNo];
        $offset = 0;
        foreach ($fields as $f) {
            $row[$f->name] = trim(substr($raw, $offset, $f->length));
            $offset += $f->length;
        }
        return $row;
    }

    // 新增一筆記錄 (原子並行寫入)
    public function insert($tableName, array $data) {
        $h = $this->getHandle($tableName);
        $fields = $this->engine->getFdt($h);

        // 依據 FDT 欄位順序組裝 CSV Payload
        $payload = [];
        foreach ($fields as $f) {
            $payload[] = isset($data[$f->name]) ? $data[$f->name] : '';
        }
        $csvData = implode(',', $payload);

        // 原生原子新增，直接將資料寫入尾端並提交
        $ok = $this->engine->append($csvData, 1, ',', $h);
        if (!$ok) {
            throw new Exception("Failed to atomically append record to table: " . $tableName);
        }
        $this->engine->commit($h);

        // 回傳新增後的最新物理 RowID
        return $this->engine->getTotalRecords($h);
    }

    // 更新指定記錄 (取代 UPDATE ... WHERE recno = ...)
    public function update($tableName, $recNo, array $data) {
        $h = $this->getHandle($tableName);
        $current = $this->readRecordMap($h, $recNo);
        if (!$current) return false;

        $fields = $this->engine->getFdt($h);
        $payload = [];
        foreach ($fields as $f) {
            $payload[] = array_key_exists($f->name, $data) ? $data[$f->name] : $current[$f->name];
        }
        $csvData = implode(',', $payload);

        $ok = $this->engine->rowReplace($csvData, $recNo, ',', $h);
        $this->engine->commit($h);
        return $ok;
    }

    // 向量批次讀取 (取代 SELECT * FROM table LIMIT offset, limit)
    public function fetchVector($tableName, $offset = 0, $limit = 200, $tagId = 0) {
        $h = $this->getHandle($tableName);
        $total = $this->engine->getLastRec($tagId, $h);
        $this->engine->goTo($offset + 1, $tagId, $h);

        $results = [];
        for ($i = 0; $i < $limit && ($offset + $i) < $total; $i++) {
            $recNo = $this->engine->getRecno($tagId, $h);
            $results[] = $this->readRecordMap($h, $recNo);
            if (!$this->engine->skip(1, $tagId, $h)) break;
        }
        return $results;
    }
}
?>