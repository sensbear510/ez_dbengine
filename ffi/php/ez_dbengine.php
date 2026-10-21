<?php

namespace EzDB;

use FFI;
use Exception;
use RuntimeException;
use InvalidArgumentException;

/**
 * 欄位定義類別
 */
class Field
{
    public string $name;
    public string $type;
    public int $length;
    public int $dec;

    public function __construct(string $name, string $type, int $length, int $dec = 0)
    {
        $this->name = $name;
        $this->type = strtoupper($type);
        $this->length = $length;
        $this->dec = $dec;
    }
}

/**
 * 遷移與操作報告類別
 */
class MigrateReport
{
    public int $status;
    public int $errorCode;
    public int $totalRecs;
    public int $recoveredRecs;
    public string $message;

    public function __construct(object $cReport)
    {
        $this->status = $cReport->status;
        $this->errorCode = $cReport->error_code;
        $this->totalRecs = $cReport->total_recs;
        $this->recoveredRecs = $cReport->recovered_recs;
        
        $msg = '';
        for ($i = 0; $i < 128; $i++) {
            if ($cReport->message[$i] === "\0") {
                break;
            }
            $msg .= $cReport->message[$i];
        }
        $this->message = $msg;
    }

    public function __toString(): string
    {
        return sprintf(
            "<MigrateReport status=%d err=%d total=%d msg='%s'>",
            $this->status,
            $this->errorCode,
            $this->totalRecs,
            $this->message
        );
    }
}

/**
 * 關聯節點投影描述
 */
class RlNode
{
    public int $ebfIndex;
    public string $fieldName;
    public string $aliasName;

    public function __construct(int $ebfIndex, string $fieldName, string $aliasName = '')
    {
        $this->ebfIndex = $ebfIndex;
        $this->fieldName = $fieldName;
        $this->aliasName = $aliasName !== '' ? $aliasName : $fieldName;
    }
}

/**
 * 關聯鍵幾何連結描述
 */
class RlLink
{
    public int $parentEbfIndex;
    public int $childEbfIndex;
    public array $parentFkOffsets;
    public array $parentFkLens;
    public string $childTagName;

    public function __construct(
        int $parentEbfIndex,
        int $childEbfIndex,
        array $parentFkOffsets,
        array $parentFkLens,
        string $childTagName
    ) {
        $this->parentEbfIndex = $parentEbfIndex;
        $this->childEbfIndex = $childEbfIndex;
        $this->parentFkOffsets = $parentFkOffsets;
        $this->parentFkLens = $parentFkLens;
        $this->childTagName = $childTagName;
    }
}

/**
 * 關聯視圖描述
 */
class RlViewDesc
{
    public string $relationName;
    public int $joinMode; // 0: EZ_RL_JOIN_LEFT, 1: EZ_RL_JOIN_INNER
    public array $ebfHandles;
    /** @var RlNode[] */
    public array $nodes;
    /** @var RlLink[] */
    public array $links;

    public function __construct(
        string $relationName,
        int $joinMode,
        array $ebfHandles,
        array $nodes,
        array $links
    ) {
        $this->relationName = $relationName;
        $this->joinMode = $joinMode;
        $this->ebfHandles = $ebfHandles;
        $this->nodes = $nodes;
        $this->links = $links;
    }
}

/**
 * ez_dbengine PHP FFI 高階封裝類別 (Singleton + Multi-WorkArea Architecture)
 */
class EzDBEngine
{
    private static ?FFI $ffi = null;
    private static ?EzDBEngine $instance = null;
    private static array $observerKeepAlive = [];
    private int $defaultHandle = 0;
    private object $cReport;

    /**
     * 取得常駐引擎單例 (Singleton)
     */
    public static function getInstance(): self
    {
        if (self::$instance === null) {
            self::$instance = new self();
        }
        return self::$instance;
    }

    /**
     * 自動偵測並回傳動態庫完整路徑
     */
    public static function resolveLibraryPath(): string
    {
        $isWin = PHP_OS_FAMILY === 'Windows';
        $ds = DIRECTORY_SEPARATOR;
        $libName = $isWin ? 'ez_dbengine.dll' : (PHP_OS_FAMILY === 'Darwin' ? 'libez_dbengine.dylib' : 'libez_dbengine.so');

        $candidatePaths = [
            __DIR__ . $ds . $libName,
            __DIR__ . "{$ds}run_win{$ds}{$libName}",
            dirname(__DIR__, 2) . "{$ds}build_win{$ds}bin{$ds}Release{$ds}{$libName}",
            dirname(__DIR__, 2) . "{$ds}build_win{$ds}bin{$ds}{$libName}",
            dirname(__DIR__, 2) . "{$ds}build_win{$ds}{$libName}",
            dirname(__DIR__, 2) . "{$ds}build_linux{$ds}lib{$ds}{$libName}",
            dirname(__DIR__, 2) . "{$ds}build_linux{$ds}{$libName}",
        ];

        foreach ($candidatePaths as $p) {
            if (file_exists($p)) {
                return realpath($p);
            }
        }

        return $libName;
    }

    /**
     * 延遲初始化 FFI 介面
     */
    public static function getFFI(): FFI
    {
        if (self::$ffi !== null) {
            return self::$ffi;
        }

        if (!extension_loaded('ffi')) {
            throw new RuntimeException("PHP FFI 擴充未啟用，請在 php.ini 中開啟 ffi.enable=true");
        }

        $libPath = self::resolveLibraryPath();

        $cdef = <<<C
            typedef uint8_t   u8;
            typedef int8_t    s8;
            typedef uint16_t  u16;
            typedef int16_t   s16;
            typedef uint32_t  u32;
            typedef int32_t   s32;
            typedef uint64_t  u64;
            typedef int64_t   s64;
            typedef float     f32;
            typedef double    f64;
            typedef bool      ez_bool;

            typedef char           ez_char;
            typedef unsigned char  ez_u8;
            typedef void*          ez_pvoid;
            typedef const void*    ez_pcvoid;
            typedef void           ez_void;
            typedef char*          ez_pchar;
            typedef const char*    ez_pcstr;
            typedef u8*            ez_pstr;

            typedef int32_t        EZ_STATUS;

            typedef struct __attribute__((packed)) {
                ez_char name[52];
                u8      type;
                u32     len;
                u8      dec;
                u8      storage;
                u32     offset;
                u8      zbf_sequence;
            } EZ_FIELD_NODE;

            typedef struct __attribute__((packed)) {
                ez_char tag_name[64];
                u32     key_len;
                u32     key_type;
                u64     root_ptr;
                u64     node_count;
                u32     is_descending;
                u32     h_slot;
                u32     field_offsets[8];
                u32     field_lens[8];
                u8      field_count;
                u8      is_unique;
                u8      _final_pad[94];
            } EZ_TAG_INFO;

            typedef struct __attribute__((packed)) {
                u32     status;
                u32     error_code;
                u64     total_recs;
                u64     recovered_recs;
                ez_char message[128];
            } EZ_MIGRATE_REPORT;

            typedef struct __attribute__((packed)) {
                ez_pvoid data_ptr;
                u32      actual_count;
                u32      total_bytes;
                u32      reserved;
            } EZ_RESULT_SET;

            typedef struct {
                u16     ebf_index;
                ez_char field_name[52];
                ez_char alias_name[52];
            } EZ_RL_NODE_DESC;

            typedef struct {
                u16     parent_ebf_index;
                u16     child_ebf_index;
                u8      fk_field_count;
                u16     parent_fk_offsets[8];
                u16     parent_fk_lens[8];
                ez_char child_tag_name[48];
            } EZ_RL_LINK_DESC;

            typedef struct {
                const ez_char*         relation_name;
                u32                    join_mode;
                const u64*             h_ebf_array;
                u16                    ebf_count;
                const EZ_RL_NODE_DESC* nodes;
                u16                    node_count;
                const EZ_RL_LINK_DESC* links;
                u16                    link_count;
            } EZ_RL_VIEW_DESC;

            typedef struct EZ_RELATION_TABLE EZ_RELATION_TABLE;
            typedef void (*EZ_STATE_OBSERVER)(u32 slot, u32 event, u64 offset, u32 len, ez_pcvoid buffer);

            EZ_STATUS ez_db_create(ez_pcstr path, const EZ_FIELD_NODE* map);
            EZ_STATUS ez_db_alter(const u64 h, ez_pcstr path, EZ_FIELD_NODE* new_map, EZ_MIGRATE_REPORT* report);
            EZ_STATUS ez_db_reconstruct(const u64 h, ez_pcstr path, EZ_MIGRATE_REPORT* report);
            u64       ez_db_use(ez_pcstr path, EZ_MIGRATE_REPORT* report);
            u64       ez_db_open(ez_pcstr path, EZ_MIGRATE_REPORT* report);
            EZ_STATUS ez_db_close(const u64 h);
            s32       ez_db_close_all(void);
            void      ez_db_set_vacuum(const u64 h, f32 threshold, u32 min_deleted);
            void      ez_db_get_name_from_path(ez_pcstr path, ez_pchar out_name, u32 max_len);

            EZ_STATUS ez_db_gotop(const u64 h, u32 tag_id, ez_pcstr tag_name);
            EZ_STATUS ez_db_gobottom(const u64 h, u32 tag_id, ez_pcstr tag_name);
            EZ_STATUS ez_db_skip(const u64 h, u32 tag_id, ez_pcstr tag_name, s32 n);
            EZ_STATUS ez_db_goto(const u64 h, u32 tag_id, ez_pcstr tag_name, u64 recno);
            ez_bool   ez_db_is_eof(const u64 h, u32 tag_id, ez_pcstr tag_name);
            ez_bool   ez_db_is_bof(const u64 h, u32 tag_id, ez_pcstr tag_name);
            ez_bool   ez_db_is_found(const u64 h, u32 tag_id, ez_pcstr tag_name);
            s64       ez_db_recno(const u64 h, u32 tag_id, ez_pcstr tag_name);
            s64       ez_db_lastrec(const u64 h, u32 tag_id, ez_pcstr tag_name);
            u32       ez_db_recsize(const u64 h);
            u64       ez_db_record_count(const u64 h);

            EZ_STATUS ez_db_seek_by_tag(const u64 h, ez_pcstr tag_name, ...);
            EZ_STATUS ez_db_seek_by_tag_id(const u64 h, u32 tag_id, ...);
            EZ_STATUS ez_db_seek_by_tag_array(const u64 h, ez_pcstr tag_name, ez_pcvoid* values);
            EZ_STATUS ez_db_seek_by_tag_id_array(const u64 h, u32 tag_id, ez_pcvoid* values);
            EZ_STATUS ez_db_locate(const u64 h, ez_pcstr fieldname, ez_pcvoid target_value, ez_bool partial_match);

            EZ_STATUS ez_db_append(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);
            EZ_STATUS ez_db_row_replace(const u64 h, u64 row_id, ez_pcvoid data, ez_pcstr delim);
            EZ_STATUS ez_db_insert(const u64 h, ez_pcvoid data, u32 rec_count, ez_pstr delim);
            EZ_STATUS ez_db_replace(const u64 h, u64 row_id, ez_pcstr fieldname, ez_pcvoid val);

            EZ_STATUS ez_db_get_record(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pvoid buffer, u32 buffer_size, ez_bool include_deleted);
            ez_bool   ez_db_is_deleted(const u64 h, u64 row_id);
            EZ_STATUS ez_db_delete(const u64 h, u64 row_id);
            EZ_STATUS ez_db_pack(const u64 h, ez_pcstr path);
            EZ_STATUS ez_db_zap(u64 h);
            EZ_STATUS ez_db_recall(const u64 h, u64 row_id);
            EZ_STATUS ez_db_commit(const u64 h);

            EZ_STATUS            ez_db_get_field_names(const u64 h, ez_pchar out_buf, u32 buf_size, ez_pcstr delim);
            EZ_STATUS            ez_db_get_index_key(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pchar out_buf, u32 out_buf_len);
            const EZ_FIELD_NODE* ez_db_get_fdt(const u64 h);
            const EZ_TAG_INFO*   ez_db_get_tags(const u64 h);
            u64                  ez_db_get_delete_count(const u64 h);
            EZ_STATUS            ez_db_get_record_vector(const u64 h, u32 tag_id, ez_pcstr tag_name, ez_pvoid out_struct_array, u32* p_count, u32 struct_size, ez_bool strip_str, ez_bool include_deleted);

            EZ_STATUS ez_db_mount_index(const u64 h, ez_pcstr edx_path, u32 slot_id);
            EZ_STATUS ez_db_create_index(const u64 h, ez_pcstr tag_name, ez_pcstr fields_str, ez_bool is_unique);
            EZ_STATUS ez_db_purge_duplicates(const u64 h, u32 tag_id, u64 keep_row_id);
            EZ_STATUS ez_db_extract_duplicates(const u64 h, u32 tag_id);

            void ez_set_state_observer(EZ_STATE_OBSERVER cb);
            void ez_db_dump_workarea(const u64 h);
            void ez_db_dump_record(const u64 h, ez_pcvoid record_payload);

            ez_pcstr ez_errstr(EZ_STATUS status);
            ez_pcstr ez_last_error(void);

            EZ_STATUS ez_rl_mgr_init(void);
            EZ_STATUS ez_rl_mgr_cleanup(void);
            u64       ez_rl_build_view(const EZ_RL_VIEW_DESC* desc);
            EZ_STATUS ez_rl_destroy_view(const u64 h_rel);
            EZ_STATUS ez_rl_get_record_vector(EZ_RELATION_TABLE* rel, u8* out_buffer, u32 request_count, u32* actual_count);
            EZ_STATUS ez_rl_save_view_file(const EZ_RL_VIEW_DESC* desc, const ez_char* erl_path);
            u64       ez_rl_load_view_file(const ez_char* erl_path, const u64* h_ebf_array, u16 ebf_count);
        C;

        self::$ffi = FFI::cdef($cdef, $libPath);
        return self::$ffi;
    }

    /**
     * 靜態建立實體資料表結構 (正確累加 offset 確保 64B FDT 映射精確)
     * @param Field[] $fields
     */
    public static function create(string $path, array $fields): int
    {
        $ffi = self::getFFI();
        $count = count($fields);
        $cFields = $ffi->new("EZ_FIELD_NODE[" . ($count + 1) . "]");
        $currentOffset = 0;

        foreach ($fields as $i => $f) {
            FFI::memcpy($cFields[$i]->name, substr($f->name, 0, 51), strlen(substr($f->name, 0, 51)));
            $cFields[$i]->type = ord($f->type[0]);
            $cFields[$i]->len = $f->length;
            $cFields[$i]->dec = $f->dec;
            $cFields[$i]->storage = 0;
            $cFields[$i]->offset = $currentOffset;
            $cFields[$i]->zbf_sequence = 0;

            $currentOffset += $f->length;
        }
        $cFields[$count]->type = 0; // 結尾 Node
        $cFields[$count]->offset = $currentOffset;

        return $ffi->ez_db_create($path, FFI::addr($cFields[0]));
    }

    /**
     * 關閉所有開啟的工作區
     */
    public static function closeAll(): int
    {
        return self::getFFI()->ez_db_close_all();
    }

    // =========================================================================
    // 錯誤診斷子系統
    // =========================================================================

    // =========================================================================
    // 錯誤診斷子系統
    // =========================================================================

    public static function errStr(int $status): string
    {
        $res = self::getFFI()->ez_errstr($status);
        if ($res === null) {
            return "Unknown engine error";
        }
        return is_string($res) ? $res : FFI::string($res);
    }

    public static function lastError(): string
    {
        $res = self::getFFI()->ez_last_error();
        if ($res === null) {
            return "";
        }
        return is_string($res) ? $res : FFI::string($res);
    }

    public static function getDetailedError(int $status): string
    {
        $dyn = self::lastError();
        $desc = self::errStr($status);
        if ($dyn !== '') {
            return "[{$desc}] {$dyn} (Code: {$status})";
        }
        return "[{$desc}] (Code: {$status})";
    }

    /**
     * 初始化引擎物件 (不綁定特定檔案)
     */
    public function __construct(?string $path = null)
    {
        $ffi = self::getFFI();
        $this->cReport = $ffi->new("EZ_MIGRATE_REPORT");

        // 若呼叫端傳入有效路徑，則同步掛載
        if ($path !== null && $path !== '') {
            $this->use($path);
        }
    }

    public function __destruct()
    {
        // 釋放自身預設句柄
        if ($this->defaultHandle !== 0) {
            $this->close($this->defaultHandle);
        }
    }

    private function resolveHandle(int $handle): int
    {
        $h = $handle !== 0 ? $handle : $this->defaultHandle;
        if ($h === 0) {
            throw new RuntimeException("No active WorkArea handle available.");
        }
        return $h;
    }

    // =========================================================================
    // 生命週期與檔案操作
    // =========================================================================

    public function use(string $path): int
    {
        $ffi = self::getFFI();
        $h = $ffi->ez_db_use($path, FFI::addr($this->cReport));

        if ($h === 0) {
            $report = new MigrateReport($this->cReport);
            $dyn = self::lastError();
            throw new RuntimeException("Failed to use database: {$path} | {$report} {$dyn}");
        }

        $this->defaultHandle = $h;
        return $h;
    }

    public function open(string $path): int
    {
        return $this->use($path);
    }

    public function close(int $handle = 0): int
    {
        $h = $handle !== 0 ? $handle : $this->defaultHandle;
        if ($h !== 0) {
            $st = self::getFFI()->ez_db_close($h);
            if ($this->defaultHandle === $h) {
                $this->defaultHandle = 0;
            }
            return $st;
        }
        return 0;
    }

    public function getHandle(): int
    {
        return $this->defaultHandle;
    }

    public function setVacuum(float $threshold, int $minDeleted, int $handle = 0): void
    {
        $h = $this->resolveHandle($handle);
        self::getFFI()->ez_db_set_vacuum($h, $threshold, $minDeleted);
    }

    public function alter(string $path, array $newFields, int $handle = 0): MigrateReport
    {
        $h = $this->resolveHandle($handle);
        $ffi = self::getFFI();
        $count = count($newFields);
        $cFields = $ffi->new("EZ_FIELD_NODE[" . ($count + 1) . "]");
        $currentOffset = 0;

        foreach ($newFields as $i => $f) {
            FFI::memcpy($cFields[$i]->name, substr($f->name, 0, 51), strlen(substr($f->name, 0, 51)));
            $cFields[$i]->type = ord($f->type[0]);
            $cFields[$i]->len = $f->length;
            $cFields[$i]->dec = $f->dec;
            $cFields[$i]->storage = 0;
            $cFields[$i]->offset = $currentOffset;
            $cFields[$i]->zbf_sequence = 0;

            $currentOffset += $f->length;
        }
        $cFields[$count]->type = 0;
        $cFields[$count]->offset = $currentOffset;

        $ret = $ffi->ez_db_alter($h, $path, FFI::addr($cFields[0]), FFI::addr($this->cReport));
        if ($ret !== 0) {
            throw new RuntimeException("Schema Alter failed with status: {$ret} | " . self::getDetailedError($ret));
        }
        return new MigrateReport($this->cReport);
    }

    public function reconstruct(string $path, int $handle = 0): MigrateReport
    {
        $h = $this->resolveHandle($handle);
        $ffi = self::getFFI();
        $ret = $ffi->ez_db_reconstruct($h, $path, FFI::addr($this->cReport));
        if ($ret !== 0) {
            throw new RuntimeException("Database Reconstruct failed with status: {$ret} | " . self::getDetailedError($ret));
        }
        return new MigrateReport($this->cReport);
    }

    // =========================================================================
    // 雙軌導航與狀態查詢
    // =========================================================================

    public function goTop(int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_gotop($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function goBottom(int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_gobottom($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function goTo(int $recNo, int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_goto($h, $tagId, $tagName !== '' ? $tagName : null, $recNo);
    }

    public function skip(int $step = 1, int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_skip($h, $tagId, $tagName !== '' ? $tagName : null, $step);
    }

    public function isEof(int $tagId = 0, int $handle = 0, string $tagName = ''): bool
    {
        $h = $this->resolveHandle($handle);
        return (bool)self::getFFI()->ez_db_is_eof($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function isBof(int $tagId = 0, int $handle = 0, string $tagName = ''): bool
    {
        $h = $this->resolveHandle($handle);
        return (bool)self::getFFI()->ez_db_is_bof($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function isFound(int $tagId = 0, int $handle = 0, string $tagName = ''): bool
    {
        $h = $this->resolveHandle($handle);
        return (bool)self::getFFI()->ez_db_is_found($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function getRecno(int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_recno($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function getLastRec(int $tagId = 0, int $handle = 0, string $tagName = ''): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_lastrec($h, $tagId, $tagName !== '' ? $tagName : null);
    }

    public function getRecordSize(int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_recsize($h);
    }

    public function getTotalRecords(int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_record_count($h);
    }

    // =========================================================================
    // 資料讀取、寫入與修改
    // =========================================================================

    public function getRecord(int $tagId = 0, int $handle = 0, string $tagName = '', bool $includeDeleted = false): ?string
    {
        $h = $this->resolveHandle($handle);
        $recSize = $this->getRecordSize($h);
        if ($recSize <= 0) return null;

        $buf = self::getFFI()->new("char[{$recSize}]");
        $res = self::getFFI()->ez_db_get_record($h, $tagId, $tagName !== '' ? $tagName : null, FFI::addr($buf), $recSize, $includeDeleted);

        return $res === 0 ? FFI::string($buf, $recSize) : null;
    }

    public function append(string $csvData, int $recCount = 1, string $delimiter = ",", int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        $ffi = self::getFFI();
        $len = strlen($delimiter);
        $cDelim = $ffi->new("uint8_t[" . ($len + 1) . "]");
        \FFI::memcpy($cDelim, $delimiter, $len);
        $cDelim[$len] = 0;
        return $ffi->ez_db_append($h, $csvData, $recCount, \FFI::addr($cDelim[0]));
    }

    public function insert(string $csvData, int $recCount = 1, string $delimiter = ",", int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        $ffi = self::getFFI();
        $len = strlen($delimiter);
        $cDelim = $ffi->new("uint8_t[" . ($len + 1) . "]");
        \FFI::memcpy($cDelim, $delimiter, $len);
        $cDelim[$len] = 0;
        return $ffi->ez_db_insert($h, $csvData, $recCount, \FFI::addr($cDelim[0]));
    }

    public function rowReplace(string $csvData, int $rowId, string $delimiter = ",", int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_row_replace($h, $rowId, $csvData, $delimiter);
    }

    public function replace(int $rowId, string $fieldName, string $val, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_replace($h, $rowId, $fieldName, $val);
    }

    public function delete(int $rowId, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_delete($h, $rowId);
    }

    public function recall(int $rowId, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_recall($h, $rowId);
    }

    public function isDeleted(int $rowId, int $handle = 0): bool
    {
        $h = $this->resolveHandle($handle);
        return (bool)self::getFFI()->ez_db_is_deleted($h, $rowId);
    }

    public function commit(int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_commit($h);
    }

    public function pack(string $path = '', int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_pack($h, $path !== '' ? $path : null);
    }

    public function zap(int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_zap($h);
    }

    // =========================================================================
    // 檢索與定位 (Seek & Locate)
    // =========================================================================

    public function seekByTag(string $tagName, string $key, int $handle = 0): bool
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_seek_by_tag($h, $tagName, $key) === 0;
    }

    public function seekByTagId(int $tagId, string $key, int $handle = 0): bool
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_seek_by_tag_id($h, $tagId, $key) === 0;
    }

    public function locate(string $fieldName, string $targetValue, int $handle = 0, bool $partialMatch = true): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_locate($h, $fieldName, $targetValue, $partialMatch);
    }

    // =========================================================================
    // 索引與標籤維護 (Index & Tags)
    // =========================================================================

    public function createIndex(string $tagName, string $fieldsStr, bool $isUnique = false, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_create_index($h, $tagName, $fieldsStr, $isUnique);
    }

    public function mountIndex(string $edxPath, int $slotId, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_mount_index($h, $edxPath, $slotId);
    }

    public function purgeDuplicates(int $tagId, int $keepRowId = 0, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_purge_duplicates($h, $tagId, $keepRowId);
    }

    public function extractDuplicates(int $tagId, int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_extract_duplicates($h, $tagId);
    }

    // =========================================================================
    // 綱要反射 (Reflection & Schema Metadata)
    // =========================================================================

    /**
     * @return Field[]
     */
    public function getFdt(int $handle = 0): array
    {
        $h = $this->resolveHandle($handle);
        $ffi = self::getFFI();
        $pNode = $ffi->ez_db_get_fdt($h);
        if ($pNode === null) return [];

        $fields = [];
        $i = 0;
        while (true) {
            $node = $pNode[$i];
            if ($node->type === 0) break;

            $name = '';
            for ($k = 0; $k < 52; $k++) {
                if ($node->name[$k] === "\0") break;
                $name .= $node->name[$k];
            }

            $fields[] = new Field($name, chr($node->type), (int)$node->len, (int)$node->dec);
            $i++;
        }
        return $fields;
    }

    /**
     * Resolves the active index key/expression (e.g. "code" or "date+code") for a specified tag.
     * Supports resolution via tagId (1~8) and/or tagName.
     *
     * @param int $tagId Slot ID (1~8); 0 indicates omitted
     * @param string|null $tagName Tag name string; null or empty indicates omitted
     * @param int $handle WorkArea fingerprint handle (0 uses default handle)
     * @param int $bufSize Buffer capacity for key string (default 128 bytes)
     * @return string|null Resolved expression string, or null on error
     */
    public function getIndexKey(int $tagId = 0, ?string $tagName = null, int $handle = 0, int $bufSize = 128): ?string
    {
        $h = $this->resolveHandle($handle);
        if ($bufSize <= 0) {
            return null;
        }

        try {
            $buf = self::getFFI()->new("char[{$bufSize}]");
            $normalizedTagName = ($tagName !== null && trim($tagName) !== '') ? trim($tagName) : null;
            $outPtr = \FFI::cast("char*", $buf);

            $status = self::getFFI()->ez_db_get_index_key($h, $tagId, $normalizedTagName, $outPtr, $bufSize);
            if ($status === 0) {
                return trim(\FFI::string($buf));
            }
        } catch (\Throwable $e) {
            return null;
        }

        return null;
    }
    
    public function getFieldNames(string $delim = ',', int $handle = 0): string
    {
        $h = $this->resolveHandle($handle);
        $buf = self::getFFI()->new("char[1024]");
        self::getFFI()->ez_db_get_field_names($h, FFI::addr($buf), 1024, $delim);
        return FFI::string($buf);
    }

    public function getDeleteCount(int $handle = 0): int
    {
        $h = $this->resolveHandle($handle);
        return self::getFFI()->ez_db_get_delete_count($h);
    }

    public function debugDumpWorkArea(int $handle = 0): void
    {
        $h = $this->resolveHandle($handle);
        self::getFFI()->ez_db_dump_workarea($h);
    }

    // =========================================================================
    // 關聯檢視管理器 (Relation Manager Subsystem)
    // =========================================================================

    public static function relationInit(): int
    {
        return self::getFFI()->ez_rl_mgr_init();
    }

    public static function relationCleanup(): int
    {
        return self::getFFI()->ez_rl_mgr_cleanup();
    }

    public function buildRelationView(RlViewDesc $desc): int
    {
        $ffi = self::getFFI();
        $cDesc = $ffi->new("EZ_RL_VIEW_DESC");
        $cDesc->relation_name = $desc->relationName;
        $cDesc->join_mode = $desc->joinMode;

        // 綁定 EBF Handles
        $ebfCount = count($desc->ebfHandles);
        $cHArray = $ffi->new("u64[{$ebfCount}]");
        foreach ($desc->ebfHandles as $i => $hVal) {
            $cHArray[$i] = $hVal;
        }
        $cDesc->h_ebf_array = FFI::addr($cHArray[0]);
        $cDesc->ebf_count = $ebfCount;

        // 綁定 Projections
        $nodeCount = count($desc->nodes);
        $cNodes = $ffi->new("EZ_RL_NODE_DESC[{$nodeCount}]");
        foreach ($desc->nodes as $i => $n) {
            $cNodes[$i]->ebf_index = $n->ebfIndex;
            FFI::memcpy($cNodes[$i]->field_name, substr($n->fieldName, 0, 51), strlen(substr($n->fieldName, 0, 51)));
            FFI::memcpy($cNodes[$i]->alias_name, substr($n->aliasName, 0, 51), strlen(substr($n->aliasName, 0, 51)));
        }
        $cDesc->nodes = FFI::addr($cNodes[0]);
        $cDesc->node_count = $nodeCount;

        // 綁定 Links
        $linkCount = count($desc->links);
        $cLinks = $ffi->new("EZ_RL_LINK_DESC[{$linkCount}]");
        foreach ($desc->links as $i => $l) {
            $cLinks[$i]->parent_ebf_index = $l->parentEbfIndex;
            $cLinks[$i]->child_ebf_index = $l->childEbfIndex;
            $cLinks[$i]->fk_field_count = count($l->parentFkOffsets);
            for ($k = 0; $k < 8; $k++) {
                $cLinks[$i]->parent_fk_offsets[$k] = $l->parentFkOffsets[$k] ?? 0;
                $cLinks[$i]->parent_fk_lens[$k] = $l->parentFkLens[$k] ?? 0;
            }
            FFI::memcpy($cLinks[$i]->child_tag_name, substr($l->childTagName, 0, 47), strlen(substr($l->childTagName, 0, 47)));
        }
        $cDesc->links = FFI::addr($cLinks[0]);
        $cDesc->link_count = $linkCount;

        $hRel = $ffi->ez_rl_build_view(FFI::addr($cDesc));
        if ($hRel === 0) {
            throw new RuntimeException("Failed to build relation view: {$desc->relationName} | " . self::lastError());
        }
        return $hRel;
    }

    public function destroyRelationView(int $hRel): int
    {
        return self::getFFI()->ez_rl_destroy_view($hRel);
    }

    public function saveRelationFile(RlViewDesc $desc, string $erlPath): int
    {
        $ffi = self::getFFI();
        $cDesc = $ffi->new("EZ_RL_VIEW_DESC");
        $cDesc->relation_name = $desc->relationName;
        $cDesc->join_mode = $desc->joinMode;

        $ebfCount = count($desc->ebfHandles);
        $cHArray = $ffi->new("u64[{$ebfCount}]");
        foreach ($desc->ebfHandles as $i => $hVal) $cHArray[$i] = $hVal;
        $cDesc->h_ebf_array = FFI::addr($cHArray[0]);
        $cDesc->ebf_count = $ebfCount;

        $nodeCount = count($desc->nodes);
        $cNodes = $ffi->new("EZ_RL_NODE_DESC[{$nodeCount}]");
        foreach ($desc->nodes as $i => $n) {
            $cNodes[$i]->ebf_index = $n->ebfIndex;
            FFI::memcpy($cNodes[$i]->field_name, substr($n->fieldName, 0, 51), strlen(substr($n->fieldName, 0, 51)));
            FFI::memcpy($cNodes[$i]->alias_name, substr($n->aliasName, 0, 51), strlen(substr($n->aliasName, 0, 51)));
        }
        $cDesc->nodes = FFI::addr($cNodes[0]);
        $cDesc->node_count = $nodeCount;

        $linkCount = count($desc->links);
        $cLinks = $ffi->new("EZ_RL_LINK_DESC[{$linkCount}]");
        foreach ($desc->links as $i => $l) {
            $cLinks[$i]->parent_ebf_index = $l->parentEbfIndex;
            $cLinks[$i]->child_ebf_index = $l->childEbfIndex;
            $cLinks[$i]->fk_field_count = count($l->parentFkOffsets);
            for ($k = 0; $k < 8; $k++) {
                $cLinks[$i]->parent_fk_offsets[$k] = $l->parentFkOffsets[$k] ?? 0;
                $cLinks[$i]->parent_fk_lens[$k] = $l->parentFkLens[$k] ?? 0;
            }
            FFI::memcpy($cLinks[$i]->child_tag_name, substr($l->childTagName, 0, 47), strlen(substr($l->childTagName, 0, 47)));
        }
        $cDesc->links = FFI::addr($cLinks[0]);
        $cDesc->link_count = $linkCount;

        return $ffi->ez_rl_save_view_file(FFI::addr($cDesc), $erlPath);
    }

    public function loadRelationFile(string $erlPath, array $ebfHandles): int
    {
        $ffi = self::getFFI();
        $ebfCount = count($ebfHandles);
        $cHArray = $ffi->new("u64[{$ebfCount}]");
        foreach ($ebfHandles as $i => $hVal) {
            $cHArray[$i] = $hVal;
        }

        $hRel = $ffi->ez_rl_load_view_file($erlPath, FFI::addr($cHArray[0]), $ebfCount);
        if ($hRel === 0) {
            throw new RuntimeException("Failed to load relation view file: {$erlPath} | " . self::lastError());
        }
        return $hRel;
    }
}