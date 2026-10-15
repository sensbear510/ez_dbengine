<?php
/**
 * =================================================================================
 * FILE: dbu_web.php - Master Workplace for ezDBUtility (Web Edition)
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * Integrated with in-process WorkAreaRegistry for high-performance schema lookup
 * =================================================================================
 */

$sdkPaths = [
    __DIR__ . '/ez_dbengine.php',
    dirname(__DIR__, 2) . '/ffi/php/ez_dbengine.php',
    __DIR__ . '/../../ffi/php/ez_dbengine.php',
    '/mnt/ez_dbengine/ffi/php/ez_dbengine.php',
];

$loaded = false;
foreach ($sdkPaths as $sdkPath) {
    if (file_exists($sdkPath)) {
        require_once $sdkPath;
        $loaded = true;
        break;
    }
}

$ffiInitError = null;

if (!$loaded) {
    $ffiInitError = "Cannot locate ez_dbengine.php SDK file in designated paths.";
} else {
    // 1. Check whether FFI extension is installed and enabled
    if (!extension_loaded('ffi')) {
        $ffiInitError = "PHP extension 'ffi' is not installed or enabled in php.ini.";
    } else {
        // 2. Check if ffi.enable directive restricts Web execution
        $ffiEnableSetting = strtolower(ini_get('ffi.enable') ?: '');
        if ($ffiEnableSetting !== 'true' && $ffiEnableSetting !== '1') {
            $ffiInitError = "FFI is restricted by 'ffi.enable = " . htmlspecialchars($ffiEnableSetting) . "'. Launch server with: php -d ffi.enable=true -S 0.0.0.0:8900";
        } else {
            // 3. Test initial binding with C-Core library
            try {
                if (!class_exists('EzDB\EzDBEngine')) {
                    throw new Exception("EzDBEngine class not found in loaded SDK.");
                }
            } catch (Throwable $e) {
                $ffiInitError = "C-Core Init Exception: " . $e->getMessage();
            }
        }
    }
}

use EzDB\EzDBEngine;
use EzDB\Field;

/**
 * Class WorkAreaRegistry
 * In-process centralized storage for active WorkAreas, field schema, and tags.
 */
class WorkAreaRegistry {
    private static array $pool = [];

    /**
     * Store WorkArea metadata for the specified physical file path
     */
    public static function set(string $path, int $handle, array $fields, array $tags, int $total, int $delCount): void {
        $realPath = realpath($path) ?: $path;

        $fieldLens = [];
        $fieldMap = [];
        foreach ($fields as $f) {
            $name = is_object($f) ? $f->name : $f['name'];
            $len = is_object($f) ? (int)$f->length : (int)$f['len'];
            $type = is_object($f) ? $f->type : $f['type'];
            $dec = is_object($f) ? (int)$f->dec : (int)$f['dec'];

            $fieldLens[strtolower($name)] = $len;
            $fieldMap[] = [
                'name' => $name,
                'type' => $type,
                'len'  => $len,
                'dec'  => $dec
            ];
        }

        $tagMap = [];
        foreach ($tags as $t) {
            $tagMap[(int)$t['slot']] = $t['name'];
            $tagMap[strtolower($t['name'])] = (int)$t['slot'];
        }

        self::$pool[$realPath] = [
            'handle'     => $handle,
            'path'       => $realPath,
            'fields'     => $fieldMap,
            'field_lens' => $fieldLens,
            'tags'       => $tagMap,
            'total'      => $total,
            'del_count'  => $delCount
        ];
    }

    /**
     * Retrieve full WorkArea metadata entry
     */
    public static function get(string $path): ?array {
        $realPath = realpath($path) ?: $path;
        return self::$pool[$realPath] ?? null;
    }

    /**
     * Retrieve specific attribute from registry
     */
    public static function getAttr(string $path, string $key, mixed $default = null): mixed {
        $entry = self::get($path);
        return $entry[$key] ?? $default;
    }

    /**
     * Remove entry from registry upon closing table
     */
    public static function remove(string $path): void {
        $realPath = realpath($path) ?: $path;
        unset(self::$pool[$realPath]);
    }
}

// Return standard JSON error response if this is an API request and FFI failed
if (isset($_GET['api']) && $ffiInitError !== null) {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'status'  => 'error',
        'message' => 'C-Core FFI Engine Failure: ' . $ffiInitError
    ]);
    exit;
}

// -----------------------------------------------------------------------------
// [Backend API Routes - Native C-Core FFI Invocations (Engine Singleton & Handle Scheduling)]
// -----------------------------------------------------------------------------
if (isset($_GET['api'])) {
    ob_start();
    header('Content-Type: application/json; charset=utf-8');
    $api = $_GET['api'];

    try {
        // Retrieve persistent C engine singleton instance
        static $engine = null;
        if ($engine === null) {
            $engine = method_exists('EzDB\EzDBEngine', 'getInstance') 
                ? EzDBEngine::getInstance() 
                : new EzDBEngine();
        }

        if ($api === 'browse_dir') {
            $isWin = PHP_OS_FAMILY === 'Windows';
            $ds = DIRECTORY_SEPARATOR;

            $rootDir = realpath(dirname(__DIR__, 2)) ?: realpath(__DIR__);
            $reqDir = !empty($_POST['dir']) ? $_POST['dir'] : $rootDir;
            $realDir = realpath($reqDir);
            if (!$realDir || !is_dir($realDir)) {
                $realDir = $rootDir;
            }

            $items = [];
            $dh = opendir($realDir);
            if ($dh) {
                while (($file = readdir($dh)) !== false) {
                    if ($file === '.') continue;

                    $fullPath = rtrim($realDir, '\\/') . $ds . $file;
                    $isDir = is_dir($fullPath);

                    if ($isDir || preg_match('/\.ebf$/i', $file)) {
                        $items[] = [
                            'name'      => $file,
                            'path'      => $fullPath,
                            'is_dir'    => $isDir,
                            'is_parent' => ($file === '..')
                        ];
                    }
                }
                closedir($dh);
            }

            usort($items, function($a, $b) {
                if ($a['is_parent']) return -1;
                if ($b['is_parent']) return 1;
                if ($a['is_dir'] !== $b['is_dir']) return $b['is_dir'] - $a['is_dir'];
                return strcasecmp($a['name'], $b['name']);
            });

            echo json_encode([
                'status'   => 'success',
                'platform' => PHP_OS_FAMILY,
                'ds'       => $ds,
                'current'  => $realDir,
                'items'    => $items
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            exit;
        }

        if ($api === 'open') {
            $path = $_POST['path'] ?? '';
            $realPath = realpath($path);
            if (!$realPath || !file_exists($realPath)) {
                throw new Exception("File not found: $path");
            }

            chdir(dirname($realPath));
            $handle = $engine->use($realPath);

            if ($handle === 0) {
                $err = EzDBEngine::getDetailedError(-104);
                throw new Exception("Unable to mount EBF WorkArea: $path | $err");
            }

            $warningMsg = null;
            $lastErr = EzDBEngine::lastError();
            if (!empty($lastErr) && stripos($lastErr, 'warning') !== false) {
                $warningMsg = $lastErr;
            }

            $fields = $engine->getFdt($handle);
            $total = $engine->getTotalRecords($handle);
            $delCount = $engine->getDeleteCount($handle);

            $tags = [];
            $cTags = EzDBEngine::getFFI()->ez_db_get_tags($handle);
            for ($i = 0; $i < 8; $i++) {
                $rawTagName = '';
                for ($k = 0; $k < 64; $k++) {
                    if ($cTags[$i]->tag_name[$k] === "\0") break;
                    $rawTagName .= $cTags[$i]->tag_name[$k];
                }

                if ($rawTagName !== '') {
                    $slotNum = $i + 1;
                    $lastRec = $engine->getLastRec($slotNum, $handle);
                    if ($lastRec > 0) {
                        $tags[] = [
                            'slot'       => $slotNum,
                            'name'       => $rawTagName,
                            'expression' => $rawTagName
                        ];
                    }
                }
            }

            $fdtData = array_map(function(Field $f) {
                return [
                    'name' => $f->name,
                    'type' => $f->type,
                    'len'  => $f->length,
                    'dec'  => $f->dec
                ];
            }, $fields);

            // Register complete schema metadata into WorkAreaRegistry
            WorkAreaRegistry::set($realPath, $handle, $fdtData, $tags, $total, $delCount);

            echo json_encode([
                'status'        => 'success',
                'handle'        => $handle,
                'total_records' => $total,
                'deleted_count' => $delCount,
                'fields'        => $fdtData,
                'tags'          => $tags,
                'warning'       => $warningMsg
            ]);
            exit;
        }

        if ($api === 'fetch_rows') {
            $path = $_POST['path'] ?? '';
            $offset = (int)($_POST['offset'] ?? 0);
            $limit = (int)($_POST['limit'] ?? 200);
            $tagId = (int)($_POST['tag_id'] ?? 0);

            $realPath = realpath($path);
            if ($realPath) {
                chdir(dirname($realPath));
            }
            $targetPath = $realPath ?: $path;

            $handle = $engine->use($targetPath);

            // Retrieve field schema from WorkAreaRegistry, with defensive fallback to getFdt
            $cachedFields = WorkAreaRegistry::getAttr($targetPath, 'fields');
            if ($cachedFields && is_array($cachedFields)) {
                $fields = $cachedFields;
            } else {
                $rawFdt = $engine->getFdt($handle);
                $fields = array_map(function(Field $f) {
                    return ['name' => $f->name, 'len' => $f->length];
                }, $rawFdt);
            }
            
            $total = ($tagId === 0) ? $engine->getTotalRecords($handle) : $engine->getLastRec($tagId, $handle);

            $rows = [];
            if ($offset < $total) {
                $engine->goTo($offset + 1, $tagId, $handle);

                for ($i = 0; $i < $limit && ($offset + $i) < $total; $i++) {
                    $raw = $engine->getRecord($tagId, $handle);
                    if ($raw === null) {
                        break;
                    }

                    $physicalRowId = $engine->getRecno($tagId, $handle);
                    $isDel = $engine->isDeleted($physicalRowId, $handle);

                    $colValues = [];
                    $cur = 0;
                    foreach ($fields as $f) {
                        $fLen = is_object($f) ? $f->length : $f['len'];
                        $fName = is_object($f) ? $f->name : $f['name'];
                        $val = substr($raw, $cur, $fLen);
                        $colValues[$fName] = trim($val);
                        $cur += $fLen;
                    }

                    $rows[] = [
                        'track_index' => $offset + $i + 1,
                        'recno'       => $physicalRowId,
                        'is_deleted'  => $isDel,
                        'data'        => $colValues
                    ];
                }
                echo json_encode(['status' => 'success', 'rows' => $rows, 'total' => $total, 'offset' => $offset]);
                exit;
            }

            echo json_encode([
                'status' => 'success', 
                'rows'   => $rows, 
                'total'  => $total, 
                'offset' => $offset
            ]);
            exit;
        }

        // -------------------------------------------------------------
        // [3] seek_locate API: Tag-Aware Seek & Locate
        // -------------------------------------------------------------
        if ($api === 'seek_locate') {
            while (ob_get_level() > 0) {
                ob_end_clean();
            }
            header('Content-Type: application/json; charset=utf-8');

            $path = $_POST['path'] ?? '';
            $mode = $_POST['mode'] ?? 'locate';
            $tagName = trim($_POST['tag_name'] ?? '');
            $tagId = (int)($_POST['tag_id'] ?? 0);
            $key = trim($_POST['key'] ?? '');
            $fieldName = trim($_POST['field_name'] ?? '');
            $startRec = (int)($_POST['start_rec'] ?? 1);
            $exactMatch = !empty($_POST['exact_match']);

            $realPath = realpath($path);
            if ($realPath) {
                chdir(dirname($realPath));
            }
            $targetPath = $realPath ?: $path;
            $handle = $engine->use($targetPath);

            try {
                if ($mode === 'seek') {
                    // 1. Resolve key padding using cached field length
                    $fieldLens = WorkAreaRegistry::getAttr($targetPath, 'field_lens', []);
                    $cleanTag = strtolower(str_replace('idx_', '', $tagName));
                    $targetLen = $fieldLens[$cleanTag] ?? ($fieldLens[strtolower($tagName)] ?? 0);

                    if ($targetLen === 0) {
                        $fields = $engine->getFdt($handle);
                        foreach ($fields as $f) {
                            if (strtolower($f->name) === $cleanTag || strtolower($f->name) === strtolower($tagName)) {
                                $targetLen = (int)$f->length;
                                break;
                            }
                        }
                    }

                    $paddedKey = ($targetLen > strlen($key)) ? str_pad($key, $targetLen, ' ', STR_PAD_RIGHT) : $key;

                    // 2. Perform native C-Core binary seek
                    $found = $engine->seekByTag($tagName, $paddedKey, $handle);
                    if (!$found && $paddedKey !== $key) {
                        $found = $engine->seekByTag($tagName, $key, $handle);
                    }

                    // 3. Now ez_db_recno directly returns the 1-based node sequence cursor of the tag!
                    $trackCursor = $found ? $engine->getRecno($tagId, $handle, $tagName) : 0;
                    $isEof = $engine->isEof($tagId, $handle, $tagName);

                    echo json_encode([
                        'status' => 'success', 
                        'found'  => $found, 
                        'recno'  => $trackCursor, // 1-based visual index on current tag track
                        'eof'    => $isEof
                    ]);
                    exit;
                } else {
                    // Locate mode (Natural track)
                    $total = $engine->getTotalRecords($handle);
                    if ($startRec > $total) {
                        echo json_encode([
                            'status' => 'success', 
                            'found'  => false, 
                            'recno'  => 0, 
                            'eof'    => true
                        ]);
                        exit;
                    }

                    $engine->goTo($startRec, 0, $handle);
                    $status = $engine->locate($fieldName, $key, $handle, !$exactMatch);

                    $isFound = ($status === 0);
                    $foundRec = $isFound ? $engine->getRecno(0, $handle) : 0;
                    $isEof = ($status !== 0) || $engine->isEof(0, $handle);

                    echo json_encode([
                        'status' => 'success', 
                        'found'  => $isFound, 
                        'recno'  => $foundRec, 
                        'eof'    => $isEof
                    ]);
                    exit;
                }
            } catch (\Throwable $e) {
                echo json_encode([
                    'status'  => 'error',
                    'message' => 'PHP Exception: ' . $e->getMessage()
                ]);
                exit;
            }
        }

        if ($api === 'update_cell') {
            $path = $_POST['path'] ?? '';
            $rowId = (int)($_POST['row_id'] ?? 0);
            $csvData = $_POST['csv_data'] ?? '';

            $handle = $engine->use($path);
            $st = $engine->rowReplace($csvData, $rowId, ',', $handle);
            $commitSt = $engine->commit($handle);

            if ($st === 0 && $commitSt === 0) {
                echo json_encode(['status' => 'success']);
            } else {
                $errCode = ($st !== 0) ? $st : $commitSt;
                echo json_encode([
                    'status'  => 'error',
                    'message' => EzDBEngine::getDetailedError($errCode)
                ]);
            }
            exit;
        }

        if ($api === 'toggle_delete') {
            $path = $_POST['path'] ?? '';
            $rowId = (int)($_POST['row_id'] ?? 0);

            $handle = $engine->use($path);
            $isDel = $engine->isDeleted($rowId, $handle);
            if ($isDel) {
                $st = $engine->recall($rowId, $handle);
            } else {
                $st = $engine->delete($rowId, $handle);
            }
            if ($st !== 0) {
                throw new Exception("Soft delete operation failed: " . EzDBEngine::getDetailedError($st));
            }
            $engine->commit($handle);
            $newDelCount = $engine->getDeleteCount($handle);

            echo json_encode([
                'status'        => 'success',
                'is_deleted'    => !$isDel,
                'deleted_count' => $newDelCount
            ]);
            exit;
        }

        if ($api === 'create_table') {
            $newPath = $_POST['new_path'] ?? '';
            $fieldsArr = json_decode($_POST['fields'] ?? '[]', true);
            $indexesArr = json_decode($_POST['indexes'] ?? '[]', true);

            if (empty($newPath)) throw new Exception("Please specify target filename");
            if (empty($fieldsArr)) throw new Exception("At least one field definition is required");

            $schema = [];
            foreach ($fieldsArr as $f) {
                $schema[] = new Field($f['name'], $f['type'], (int)$f['len'], (int)$f['dec']);
            }

            $targetFile = (basename($newPath) === $newPath) ? __DIR__ . '/' . $newPath : $newPath;
            $createSt = EzDBEngine::create($targetFile, $schema);
            if ($createSt !== 0) {
                throw new Exception("Failed to create physical EBF file: " . EzDBEngine::getDetailedError($createSt));
            }

            if (!empty($indexesArr)) {
                $db = new EzDBEngine($targetFile);
                foreach ($indexesArr as $idx) {
                    $idxSt = $db->createIndex($idx['name'], $idx['expr'], !empty($idx['unique']));
                    if ($idxSt !== 0) {
                        throw new Exception("Failed to create index [{$idx['name']}]: " . EzDBEngine::getDetailedError($idxSt));
                    }
                }
            }

            echo json_encode(['status' => 'success', 'path' => $targetFile]);
            exit;
        }

        if ($api === 'fetch_relation_rows') {
            $masterPath = $_POST['master_path'] ?? '';
            $childPath = $_POST['child_path'] ?? '';
            $childTagName = $_POST['child_tag'] ?? '';
            $offset = (int)($_POST['offset'] ?? 0);
            $limit = (int)($_POST['limit'] ?? 200);

            if (!file_exists($masterPath) || !file_exists($childPath)) {
                throw new Exception("Relation table files do not exist");
            }

            $dbMaster = new EzDBEngine($masterPath);
            $dbChild = new EzDBEngine($childPath);

            $mFields = $dbMaster->getFdt();
            $cFields = $dbChild->getFdt();
            $total = $dbMaster->getTotalRecords();

            $dbMaster->goTo($offset + 1, 0);

            $rows = [];
            for ($i = 0; $i < $limit && ($offset + $i) < $total; $i++) {
                $mRaw = $dbMaster->getRecord(0);
                if ($mRaw === null) break;

                $mCol = [];
                $cur = 0;
                foreach ($mFields as $f) {
                    $mCol[$f->name] = trim(substr($mRaw, $cur, $f->length));
                    $cur += $f->length;
                }

                $joinKey = $mCol['code'] ?? ($mCol['ID'] ?? '');
                $childFound = $dbChild->seekByTag($childTagName, $joinKey);
                $cCol = [];
                if ($childFound) {
                    $cRaw = $dbChild->getRecord();
                    $curC = 0;
                    foreach ($cFields as $cf) {
                        $cCol[$cf->name] = trim(substr($cRaw, $curC, $cf->length));
                        $curC += $cf->length;
                    }
                } else {
                    foreach ($cFields as $cf) $cCol[$cf->name] = '';
                }

                $rows[] = [
                    'recno'  => $offset + $i + 1,
                    'master' => $mCol,
                    'child'  => $cCol
                ];

                if ($dbMaster->skip(1, 0) !== 0) break;
            }

            echo json_encode(['status' => 'success', 'rows' => $rows, 'total' => $total, 'offset' => $offset]);
            exit;
        }

        if ($api === 'save_erl') {
            $name = $_POST['name'] ?? 'relation.erl';
            $data = $_POST['data'] ?? '{}';
            $path = __DIR__ . '/' . basename($name);
            file_put_contents($path, $data);
            echo json_encode(['status' => 'success', 'path' => $path]);
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
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ezDBUtility</title>
    <style>
        :root {
            --bg-color: #17181c;
            --surface-color: #202227;
            --card-color: #282a30;
            --card-dark: #1e1f23;
            --accent-amber: #e59b24;
            --accent-amber-light: #f5b041;
            --accent-red: #e74c3c;
            --accent-green: #2ecc71;
            --border-color: rgba(255, 255, 255, 0.08);
            --border-subtle: #333640;
            --text-main: #e0e2e8;
            --text-muted: #8c909c;
            --font-ui: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            --font-mono: "Consolas", "Courier New", monospace;
        }

        * { box-sizing: border-box; margin: 0; padding: 0; user-select: none; }
        body {
            background-color: var(--bg-color); color: var(--text-main); font-family: var(--font-ui);
            height: 100vh; display: flex; flex-direction: column; overflow: hidden; position: relative;
        }

        /* 1. Top MenuBar (36px) Aligned with desktop_main_page.dart */
        .top-menubar {
            height: 36px; background-color: #1a1b1f; display: flex;
            align-items: center; padding: 0 14px; border-bottom: 1px solid var(--border-color);
            gap: 16px; font-size: 12px; position: relative; z-index: 1000;
        }
        .menu-title-logo { font-size: 12px; font-weight: 600; color: #fff; display: flex; align-items: center; gap: 8px; margin-right: 6px; }
        .dropdown-menu { position: relative; display: inline-block; }
        .menu-btn {
            background: none; border: none; color: #b8bac2; cursor: pointer;
            font-size: 12px; padding: 5px 8px; border-radius: 4px;
        }
        .menu-btn:hover { color: #fff; background: rgba(255,255,255,0.06); }
        .dropdown-content {
            display: none; position: absolute; top: 100%; left: 0;
            background-color: #202227; min-width: 220px; box-shadow: 0 8px 24px rgba(0,0,0,0.85);
            border: 1px solid var(--border-subtle); border-radius: 4px; padding: 4px 0; z-index: 1100;
        }
        .dropdown-menu:hover .dropdown-content { display: block; }
        .dropdown-item {
            padding: 6px 14px; font-size: 11px; color: #ccc; cursor: pointer;
            display: flex; justify-content: space-between; align-items: center;
        }
        .dropdown-item:hover:not(.disabled) { background: rgba(229, 155, 36, 0.15); color: #fff; }
        .dropdown-item.disabled {
            color: #555 !important;
            cursor: not-allowed !important;
            pointer-events: none !important;
        }
        .dropdown-item.disabled .item-key { color: #444 !important; }
        .dropdown-divider { height: 1px; background: rgba(255,255,255,0.08); margin: 4px 0; }
        .item-key { color: #777; font-size: 10px; font-family: var(--font-mono); }

        /* 2. WorkArea Multi-Tab Ribbon (TabBar: 32px) - Hidden by default */
        .workarea-tabbar {
            height: 32px; background-color: var(--bg-color); display: none;
            align-items: center; padding: 0 8px; gap: 4px; overflow-x: auto;
            border-bottom: 1px solid var(--border-color);
        }
        .tab-item {
            display: flex; align-items: center; gap: 8px; padding: 5px 14px;
            background: #202227; border: 1px solid var(--border-color);
            border-bottom: none; border-radius: 4px 4px 0 0;
            font-size: 11px; cursor: pointer; color: var(--text-muted);
        }
        .tab-item.active {
            background: var(--card-color); color: #fff; font-weight: 600;
            border-top: 2px solid var(--accent-amber);
        }
        .tab-item .close-btn { font-size: 12px; margin-left: 4px; border-radius: 50%; padding: 0 3px; }
        .tab-item .close-btn:hover { background: rgba(255,255,255,0.2); }

        /* 3. Header Shell (88px) */
        .header-shell {
            height: 88px; background-color: var(--surface-color); display: flex;
            align-items: center; padding: 8px 14px; gap: 14px; border-bottom: 1px solid var(--border-color);
        }
        .ebf-anchor-card {
            width: 150px; height: 72px; padding: 8px 10px; background: var(--card-dark);
            border-radius: 6px; border: 1px solid var(--border-subtle); display: flex;
            align-items: center; gap: 10px; cursor: pointer;
        }
        .anchor-icon { font-size: 20px; color: var(--accent-amber); }
        .anchor-text-sub { font-size: 10px; color: var(--text-muted); }
        .anchor-text-name { font-size: 11px; font-weight: 700; color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 90px; }

        .slot-ribbon { display: flex; gap: 10px; overflow-x: auto; flex: 1; height: 72px; align-items: center; }
        .slot-card {
            width: 135px; height: 68px; padding: 8px 10px; background: var(--card-dark);
            border: 1px solid var(--border-subtle); border-radius: 6px; cursor: pointer;
            display: flex; flex-direction: column; justify-content: space-between;
        }
        .slot-card:hover { border-color: #666; }
        .slot-card.active {
            background: rgba(229, 155, 36, 0.12); border: 2px solid var(--accent-amber);
        }
        .slot-card-header { display: flex; justify-content: space-between; align-items: center; font-size: 11px; font-weight: 700; color: #7f828a; }
        .slot-card.active .slot-card-header { color: var(--accent-amber); }
        .slot-card-expr { font-size: 11px; font-family: var(--font-mono); color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        
        /* 4. Smart Seek Bar (48px) */
        .smart-seek-bar {
            height: 48px; background-color: var(--card-color); display: flex;
            align-items: center; padding: 6px 10px; gap: 10px; border-bottom: 1px solid var(--border-color);
        }
        .seek-label { font-size: 12px; font-weight: 700; color: var(--accent-green); display: flex; align-items: center; gap: 6px; white-space: nowrap; }
        .seek-input {
            flex: 1; width: 100%; height: 32px; background: #121316;
            border: 1px solid var(--border-subtle); color: #fff; padding: 0 10px;
            border-radius: 4px; font-size: 12px; font-family: var(--font-mono); outline: none;
        }
        .seek-input:focus { border-color: var(--accent-amber); }
        .btn-seek {
            height: 32px; background: #2e7d32; border: none; color: #fff;
            font-size: 11px; font-weight: 800; padding: 0 18px; border-radius: 4px;
            cursor: pointer; display: flex; align-items: center; gap: 6px;
        }
        .btn-seek.seek-mode { background: var(--accent-amber) !important; color: #17181c !important; }

        /* 5. Virtualized DataGrid Workplace (Aligned with desktop_main_page) */
        .datagrid-container {
            flex: 1; overflow-y: scroll; overflow-x: auto; position: relative; background: var(--bg-color); outline: none;
        }
        .datagrid-virtual-scroller {
            position: relative; width: 100%; min-width: 100%;
        }
        table { border-collapse: collapse; width: 100%; font-size: 12px; font-family: var(--font-mono); }
        th {
            height: 36px; background: #1f2025; color: var(--accent-amber);
            text-align: left; padding: 0 10px; border-bottom: 1px solid var(--border-color);
            border-right: 1px solid var(--border-color); position: sticky; top: 0; z-index: 10; font-weight: 700;
        }
        td {
            height: 36px; padding: 0 10px; border-bottom: 1px solid rgba(255,255,255,0.03);
            border-right: 1px solid rgba(255,255,255,0.03); white-space: nowrap;
        }
        tr.even-row { background: #1c1d22; }
        tr.odd-row { background: #17181c; }
        tr:hover { background: rgba(229, 155, 36, 0.08); }

        .frozen-act { position: sticky; left: 0; width: 70px; background: #1f2025; z-index: 5; text-align: center; }
        .frozen-num { position: sticky; left: 70px; width: 50px; background: #1f2025; z-index: 5; text-align: center; }
        .frozen-zap { position: sticky; left: 120px; width: 24px; background: #1f2025; z-index: 5; text-align: center; color: var(--accent-red); font-weight: 800; }

        tr.selected { background: rgba(52, 152, 219, 0.22) !important; }
        tr.selected .frozen-num { color: var(--accent-amber); font-weight: 800; }
        td.cell-focused {
            border: 2px solid var(--accent-amber) !important;
            background: rgba(229, 155, 36, 0.25) !important; color: #fff !important; font-weight: 700;
        }
        tr.is-deleted td { color: var(--accent-red) !important; text-decoration: line-through; }

        .empty-placeholder {
            height: 100%; display: flex; flex-direction: column;
            align-items: center; justify-content: center; gap: 14px; color: #4e5058;
        }

        /* 6. Bottom TOOLBOX Bar (36px) */
        .toolbox-bar {
            height: 36px; background-color: #1a1b1f; display: flex;
            align-items: center; padding: 0 14px; border-top: 1px solid var(--border-color);
            gap: 16px; font-size: 11px;
        }
        .toolbox-title { font-weight: 800; color: var(--accent-amber); display: flex; align-items: center; gap: 6px; }
        .tool-btn {
            background: transparent; border: 1px solid transparent; color: var(--text-muted);
            padding: 4px 10px; border-radius: 4px; cursor: pointer; display: flex;
            align-items: center; gap: 6px; font-size: 11px; font-weight: 600;
        }
        .tool-btn:hover { color: #fff; background: rgba(255,255,255,0.06); }
        .tool-btn.active {
            background: rgba(229, 155, 36, 0.15); border-color: var(--accent-amber); color: var(--accent-amber);
        }

        /* 7. Classic Status Bar (24px) */
        .statusbar {
            height: 24px; background-color: #131417; display: flex;
            align-items: center; padding: 0 10px; border-top: 1px solid var(--border-color);
            font-size: 11px; font-family: var(--font-mono); gap: 12px; color: #888;
        }
        .st-badge { font-weight: 700; color: #555; }
        .st-badge.active { color: var(--accent-amber); }

        /* 8. Collapsible Toolchain Drawer */
        .toolchain-drawer {
            position: absolute; top: 156px; bottom: 24px; left: 0; right: 0;
            background: #202227; border-top: 2px solid var(--accent-amber);
            box-shadow: 0 -12px 36px rgba(0,0,0,0.95); display: none; flex-direction: column;
            z-index: 2000;
        }
        .toolchain-drawer.open { display: flex; }
        .drawer-header {
            height: 36px; background: #17181c; display: flex; justify-content: space-between;
            align-items: center; padding: 0 16px; border-bottom: 1px solid var(--border-color);
            font-size: 12px; font-weight: 700; color: var(--accent-amber);
        }
        .drawer-body { flex: 1; display: flex; overflow: hidden; padding: 12px; gap: 16px; }

        /* Common Modal Dialog Styles */
        .modal-overlay {
            position: fixed; top: 0; left: 0; right: 0; bottom: 0;
            background: rgba(0,0,0,0.65); backdrop-filter: blur(4px);
            display: none; justify-content: center; align-items: center; z-index: 10000;
        }
        .modal-card {
            background: #202227; border: 1px solid var(--accent-amber);
            border-radius: 8px; box-shadow: 0 16px 36px rgba(0,0,0,0.85);
            display: flex; flex-direction: column; width: 620px; height: 440px; overflow: hidden;
        }
        .explorer-row {
            display: flex; align-items: center; gap: 8px; padding: 6px 12px;
            border-radius: 4px; cursor: pointer; font-size: 12px; font-family: var(--font-mono);
        }
        .explorer-row:hover { background: rgba(255,255,255,0.05); }
        .explorer-row.selected { background: rgba(229, 155, 36, 0.2); color: #fff; font-weight: 700; }

        /* RWD */
        @media screen and (max-width: 1024px) {
            .toolchain-drawer { top: 80px; }
        }

        @media screen and (max-width: 600px) {
            .header-shell { height: auto; flex-direction: column; align-items: stretch; padding: 8px 10px; gap: 8px; }
            .ebf-anchor-card { width: 100%; height: 48px; }
            .slot-ribbon { width: 100%; height: 54px; }
            .slot-card { width: 110px; height: 48px; padding: 4px 6px; }
            .smart-seek-bar { height: auto; flex-wrap: wrap; padding: 8px 10px; }
            .seek-input { max-width: 100%; }
            .frozen-act { width: 44px; }
            .frozen-num { width: 38px; left: 44px; }
            .frozen-zap { left: 82px; }
            .toolchain-drawer { top: 0; bottom: 0; border-top: none; z-index: 3000; }
            .drawer-body { flex-direction: column; padding: 8px; gap: 10px; overflow-y: auto; }
            .modal-card { width: 95vw !important; height: 85vh !important; }
        }

        /* Toast Panel */
        .toast-container {
            position: fixed; top: 48px; right: 20px; display: flex; flex-direction: column;
            gap: 10px; z-index: 100000; pointer-events: none;
        }
        .toast-panel {
            min-width: 340px; max-width: 480px; background: #1e2025; border-radius: 6px;
            box-shadow: 0 12px 32px rgba(0, 0, 0, 0.75); padding: 12px 16px; display: flex;
            align-items: flex-start; gap: 12px; pointer-events: auto; transform: translateX(120%);
            opacity: 0; transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s ease;
            border-left: 4px solid var(--accent-amber); border-top: 1px solid rgba(255, 255, 255, 0.08);
            border-right: 1px solid rgba(255, 255, 255, 0.08); border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }
        .toast-panel.show { transform: translateX(0); opacity: 1; }
        .toast-panel.warning { border-left-color: var(--accent-amber); }
        .toast-panel.error { border-left-color: var(--accent-red); }
        .toast-panel.info { border-left-color: #3498db; }
        .toast-icon { font-size: 18px; line-height: 1.2; }
        .toast-content { flex: 1; display: flex; flex-direction: column; gap: 4px; }
        .toast-title { font-size: 12px; font-weight: 700; color: #fff; letter-spacing: 0.5px; }
        .toast-panel.warning .toast-title { color: var(--accent-amber); }
        .toast-panel.error .toast-title { color: var(--accent-red); }
        .toast-message { font-size: 11px; color: #bbb; line-height: 1.5; word-break: break-all; font-family: var(--font-ui); }
        .toast-close { cursor: pointer; color: #777; font-size: 14px; line-height: 1; padding: 2px; }
        .toast-close:hover { color: #fff; }
    </style>
</head>
<body>

    <div class="toast-container" id="toastContainer"></div>

    <div id="ffiCrashBar" style="<?php echo $ffiInitError ? 'display:flex;' : 'display:none;'; ?> position:fixed; top:0; left:0; right:0; height:40px; background:#b71c1c; color:#fff; z-index:99999; align-items:center; padding:0 16px; font-size:12px; font-weight:700; box-shadow:0 4px 16px rgba(0,0,0,0.8); gap:12px; border-bottom:1px solid #ff5252;">
        <span style="font-size:16px;">🚨</span>
        <span style="letter-spacing:0.5px;">[C-CORE FFI FAILURE]:</span>
        <span id="ffiCrashMsg" style="font-family:var(--font-mono); font-weight:normal; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
            <?php echo htmlspecialchars($ffiInitError ?? ''); ?>
        </span>
        <button onclick="location.reload()" style="background:#fff; color:#b71c1c; border:none; padding:4px 12px; font-size:11px; font-weight:800; border-radius:4px; cursor:pointer;">Press F5 to Reload</button>
    </div>

    <div id="ffiLockdownOverlay" style="<?php echo $ffiInitError ? 'display:flex;' : 'display:none;'; ?> position:fixed; top:40px; left:0; right:0; bottom:0; background:rgba(10, 11, 14, 0.88); backdrop-filter:blur(6px); z-index:99998; flex-direction:column; align-items:center; justify-content:center; gap:16px;">
        <div style="font-size:54px; opacity:0.6;">🔒</div>
        <div style="font-size:16px; font-weight:800; color:#ff5252; letter-spacing:0.5px;">WorkArea Locked Down</div>
        <div style="font-size:12px; color:#aaa; max-width:540px; text-align:center; line-height:1.6;">
            The underlying C-Core engine (<code>ez_dbengine.so</code> / <code>.dll</code>) failed to load via PHP FFI.<br>
            All table I/O, EDX navigation, and schema operations are strictly disabled to prevent memory corruption.<br>
            Please verify shared library paths and permissions, then press <strong>F5</strong> to retry.
        </div>
    </div>

    <!-- 1. Top MenuBar (36px) -->
    <div class="top-menubar">
        <div class="menu-title-logo"><span style="color:var(--accent-amber);">🪙</span> ezDBUtility</div>
        
        <div class="dropdown-menu">
            <button class="menu-btn">File</button>
            <div class="dropdown-content">
                <div class="dropdown-item" onclick="handleNewSchema()"><span>New Table</span><span class="item-key">Ctrl+N</span></div>
                <div class="dropdown-item" onclick="openFileExplorer()"><span>Open EBF</span><span class="item-key">Ctrl+O</span></div>
                <div class="dropdown-item" onclick="saveCurrentTab()"><span>Save</span><span class="item-key">Ctrl+S</span></div>
                <div class="dropdown-item" onclick="saveAllTabs()"><span>Save All</span><span class="item-key">Ctrl+Alt+S</span></div>
                <div class="dropdown-item" onclick="closeCurrentTab()"><span>Close Tab</span><span class="item-key">Ctrl+F4</span></div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-item" onclick="toggleDrawer('relation')"><span>Save Relation</span></div>
                <div class="dropdown-item" onclick="toggleDrawer('relation')"><span>Load Relation</span></div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-item" onclick="alert('Pack Database Triggered')"><span>Pack DB</span></div>
            </div>
        </div>

        <div class="dropdown-menu">
            <button class="menu-btn">Edit</button>
            <div class="dropdown-content">
                <div class="dropdown-item" onclick="activateLocate()"><span>Find Keyword</span><span class="item-key">Ctrl+F</span></div>
                <div class="dropdown-item" onclick="openModal('#goToRowModal')"><span>Go To Row</span><span class="item-key">Ctrl+G</span></div>
                <div class="dropdown-divider"></div>
                <div id="menuIndexSlotContainer"></div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-item" onclick="toggleDeleteActive()"><span>Delete Toggle</span><span class="item-key">Delete</span></div>
            </div>
        </div>

        <div class="dropdown-menu">
            <button class="menu-btn">Tools</button>
            <div class="dropdown-content">
                <div class="dropdown-item" onclick="toggleDrawer('schema')"><span>Schema Designer</span></div>
                <div class="dropdown-item" onclick="toggleDrawer('relation')"><span>Relation Studio</span></div>
                <div class="dropdown-divider"></div>
                <div class="dropdown-item" onclick="openModal('#aboutModal')"><span>About</span></div>
            </div>
        </div>
    </div>

    <!-- 2. WorkArea Multi-Tab Bar (TabBar: 32px) -->
    <div class="workarea-tabbar" id="tabBar"></div>

    <!-- 3. Header Shell (88px) -->
    <div class="header-shell">
        <div class="ebf-anchor-card" onclick="openFileExplorer()">
            <span class="anchor-icon">📁</span>
            <div>
                <div class="anchor-text-sub">EBF Anchor</div>
                <div class="anchor-text-name" id="anchorFileName">No Table Ope...</div>
            </div>
        </div>
        <div class="slot-ribbon" id="slotRibbon">
            <div style="font-size: 11px; color: #555; margin-left: 10px;" id="noEdxHint">No EDX Index Attached</div>
        </div>
    </div>

    <!-- 4. Smart Seek Bar (48px) -->
    <div class="smart-seek-bar">
        <span class="seek-label" id="seekLabel">🔍 Locate:</span>
        <input type="text" class="seek-input" id="seekInput" placeholder="Enter search keyword (Ctrl+F to focus, F3 to seek)..." />
        <button class="btn-seek" id="btnSeek" onclick="executeSeek()">➔ Locate (F3)</button>
    </div>

    <!-- 5. Virtualized DataGrid Workplace -->
    <div class="datagrid-container" id="gridContainer" tabindex="0" onscroll="onGridScroll()">
        <div class="empty-placeholder" id="emptyPlaceholder">
            <div style="font-size: 48px; opacity: 0.3;">📂</div>
            <div style="font-size: 14px; font-weight: 600;">No dataset loaded in active WorkArea</div>
        </div>
        
        <div class="datagrid-virtual-scroller" id="virtualScroller" style="display: none;">
            <table id="dataTable">
                <thead id="tableHeader"></thead>
                <tbody id="tableBody"></tbody>
            </table>
        </div>
    </div>

    <!-- 6. Toolchain Drawer -->
    <div class="toolchain-drawer" id="toolchainDrawer">
        <div class="drawer-header">
            <span id="drawerTitle">WORKBENCH</span>
            <span style="cursor: pointer;" onclick="closeDrawer()">✕ Close</span>
        </div>
        <div class="drawer-body">
            <?php include __DIR__ . '/widgets/schema_designer.php'; ?>
            <?php include __DIR__ . '/widgets/relation_studio.php'; ?>
        </div>
    </div>

    <!-- 7. Bottom TOOLBOX Navigation Bar (36px) -->
    <div class="toolbox-bar" id="toolboxBar">
        <div class="toolbox-title"><span>🛠️</span> TOOLBOX:</div>
        <button class="tool-btn" id="btnRelToggle" onclick="toggleDrawer('relation')">
            <span>🔗</span> Build Relation (Studio) ⌃
        </button>
        <button class="tool-btn" id="btnSchemaToggle" onclick="toggleDrawer('schema')">
            <span>📐</span> Maintain Schema ⌃
        </button>
    </div>

    <!-- 8. Classic Status Bar (24px) -->
    <div class="statusbar">
        <span id="stFile">READY</span>
        <span id="stSeparator" style="display:none;">|</span>
        <span id="stRec" style="display:none;">REC: 0 / 0</span>
        <span class="st-badge" id="stBof" style="display:none;">BOF</span>
        <span class="st-badge" id="stEof" style="display:none;">EOF</span>
        <span id="stMode" style="display:none; color: var(--accent-green); font-weight: 700;">MODE: Locate</span>
        <span id="stDel" style="display:none;">DEL: 0</span>
        <span style="margin-left: auto; color: var(--accent-amber); font-weight: 700;">R/W</span>
    </div>

    <!-- Server File Explorer Modal Dialog -->
    <div class="modal-overlay" id="fileExplorerModal">
        <div class="modal-card">
            <div style="padding: 10px 14px; background: #17181c; font-weight: 700; font-size: 12px; display: flex; justify-content: space-between; border-bottom: 1px solid var(--border-color);">
                <span>📁 Server File Explorer (Select .ebf)</span>
                <span style="cursor: pointer;" onclick="closeModal('#fileExplorerModal')">✕</span>
            </div>
            <div style="padding: 6px 12px; background: #121316; display: flex; gap: 8px; border-bottom: 1px solid var(--border-color);">
                <input type="text" id="expCurrentPath" readonly style="flex:1; background:transparent; border:none; color:#888; font-family:var(--font-mono); font-size:11px;" />
                <button onclick="explorerUp()" style="padding:2px 8px; background:var(--card-color); border:1px solid #444; color:#fff; cursor:pointer; border-radius: 2px;">⬆ Up</button>
            </div>
            <div style="flex: 1; overflow-y: auto; padding: 6px;" id="explorerList"></div>
            <div style="padding: 8px 12px; background: #17181c; display: flex; justify-content: flex-end; gap: 8px; border-top: 1px solid var(--border-color);">
                <button onclick="closeModal('#fileExplorerModal')" style="padding:4px 10px; background:transparent; border:1px solid #555; color:#aaa; cursor:pointer;">Cancel</button>
                <button id="btnExpConfirm" onclick="confirmOpenExplorer()" style="padding:4px 14px; background:var(--accent-amber); border:none; color:#17181c; font-weight:700; cursor:pointer;" disabled>Open EBF</button>
            </div>
        </div>
    </div>

    <!-- Go To Row Modal Dialog -->
    <div class="modal-overlay" id="goToRowModal">
        <div class="modal-card" style="width: 320px; height: 160px;">
            <div style="padding: 10px 14px; background: #17181c; font-weight: 700; font-size: 12px; border-bottom: 1px solid var(--border-color);">Go To Row</div>
            <div style="padding: 16px;">
                <input type="number" id="inputGoTo" min="1" style="width:100%; height:32px; background:#000; border:1px solid var(--accent-amber); color:#fff; padding:0 8px; font-family:var(--font-mono); border-radius: 4px;" />
            </div>
            <div style="padding: 8px 14px; background: #17181c; display: flex; justify-content: flex-end; gap: 8px; border-top: 1px solid var(--border-color);">
                <button onclick="closeModal('#goToRowModal')" style="background:transparent; border:none; color:#aaa; cursor:pointer;">Cancel</button>
                <button onclick="executeGoTo()" style="background:var(--accent-amber); border:none; color:#17181c; font-weight:700; padding:4px 12px; cursor:pointer; border-radius: 4px;">Jump</button>
            </div>
        </div>
    </div>

    <!-- About Modal Dialog -->
    <div class="modal-overlay" id="aboutModal">
        <div class="modal-card" style="width: 380px; height: 200px;">
            <div style="padding: 10px 14px; background: #17181c; font-weight: 700; font-size: 12px; border-bottom: 1px solid var(--border-color);">About ezDBUtility</div>
            <div style="padding: 16px; font-size: 12px; line-height: 1.6; color: #ccc;">
                <strong>ezDBUtility Web Workstation 2.0</strong><br>
                Craftsman Precision Data Engine Suite.<br>
                Backend: PHP 8.3 FFI + ez_dbengine C-Core.<br>
                UI: Virtualized On-Demand Chunk Buffer Architecture.
            </div>
            <div style="padding: 8px 14px; background: #17181c; display: flex; justify-content: flex-end; border-top: 1px solid var(--border-color);">
                <button onclick="closeModal('#aboutModal')" style="background:var(--accent-amber); border:none; color:#17181c; font-weight:700; padding:4px 14px; cursor:pointer; border-radius: 4px;">OK</button>
            </div>
        </div>
    </div>

    <!-- JavaScript Driver Core -->
    <script>
    
    function showToast(title, message, type = 'info', duration = 4500) {
        const container = document.getElementById('toastContainer');
        if (!container) return;

        const icons = {
            info: 'ℹ️',
            warning: '⚠️',
            error: '🚨'
        };

        const panel = document.createElement('div');
        panel.className = `toast-panel ${type}`;
        panel.innerHTML = `
            <span class="toast-icon">${icons[type] || '🔔'}</span>
            <div class="toast-content">
                <span class="toast-title">${title}</span>
                <span class="toast-message">${message}</span>
            </div>
            <span class="toast-close" onclick="this.closest('.toast-panel').remove()">✕</span>
        `;

        container.appendChild(panel);

        requestAnimationFrame(() => {
            panel.classList.add('show');
        });

        if (duration > 0) {
            setTimeout(() => {
                panel.classList.remove('show');
                setTimeout(() => panel.remove(), 320);
            }, duration);
        }
    }
    
    function postApi(action, data, cb) {
        const fd = new FormData();
        for (let k in data) fd.append(k, data[k]);
        fetch('?api=' + action, { method: 'POST', body: fd })
            .then(async r => {
                const text = await r.text();
                try {
                    return JSON.parse(text);
                } catch (e) {
                    console.error('[API Server Output Error]:', text);
                    throw e;
                }
            })
            .then(cb)
            .catch(err => console.error('API Error:', err));
    }

    // -------------------------------------------------------------
    // Global Workplace & Virtualized Chunk Buffer State
    // -------------------------------------------------------------
    const kRowHeight = 36.0;
    const kChunkSize = 200;
    const kMaxCacheChunks = 10;

    const isFfiAvailable = <?php echo ($ffiInitError === null) ? 'true' : 'false'; ?>;

    let openedTabs = [];
    let currentPath = '';
    let currentFields = [];
    let currentTags = [];
    let currentTagId = 0;
    let totalRecords = 0;

    let selectedRowIdx = 0;
    let selectedColIdx = 0;
    let activeTool = null;
    let relJoinMode = 0;

    let mapRowCache = new Map();
    let setLoadingChunks = new Set();

    function clearDataBuffer() {
        mapRowCache.clear();
        setLoadingChunks.clear();
    }

    // =========================================================================
    // 1. Open EBF File & Dynamic Component Expansion
    // =========================================================================
    function openEbf(path) {
        postApi('open', { path: path }, function(res) {
            if (res.status === 'success') {
                currentPath = path;
                currentFields = res.fields;
                currentTags = res.tags;
                totalRecords = res.total_records;
                selectedRowIdx = 0;

                const fname = path.split(/[\/\\]/).pop();
                if (!openedTabs.includes(path)) openedTabs.push(path);
                renderTabs();

                document.getElementById('tabBar').style.display = 'flex';
                document.getElementById('toolboxBar').style.display = 'flex';
                document.getElementById('emptyPlaceholder').style.display = 'none';
                document.getElementById('virtualScroller').style.display = 'block';
                document.getElementById('noEdxHint').style.display = 'none';
                updateCommandEnablement(true);

                document.getElementById('anchorFileName').innerText = fname;
                document.getElementById('stFile').innerText = 'FILE: ' + fname;
                document.getElementById('stRec').innerText = `REC: 1 / ${totalRecords}`;
                document.getElementById('stDel').innerText = `DEL: ${res.deleted_count}`;
                
                ['stSeparator', 'stRec', 'stBof', 'stEof', 'stMode', 'stDel'].forEach(id => {
                    document.getElementById(id).style.display = 'inline-block';
                });

                document.getElementById('txtSchemaEbfPath').value = path;

                renderSlotRibbon(res.tags);
                updateIndexSlotMenu();
                renderTableHeaders(res.fields);

                clearDataBuffer();
                initVirtualScroller();
                document.getElementById('gridContainer').focus();

                if (res.warning) {
                    showToast('Index Mount Notice', res.warning, 'warning', 6000);
                }
            } else {
                showToast('Open Failed', res.message || 'Unable to access specified EBF file', 'error', 5000);
            }
        });
    }

    function renderTabs() {
        const bar = document.getElementById('tabBar');
        bar.innerHTML = '';
        openedTabs.forEach(t => {
            const fname = t.split(/[\/\\]/).pop();
            const isActive = (t === currentPath);
            const div = document.createElement('div');
            div.className = 'tab-item' + (isActive ? ' active' : '');
            div.innerHTML = `<span>📊 ${fname}</span><span class="close-btn" onclick="closeTab('${t}', event)">✕</span>`;
            div.onclick = () => openEbf(t);
            bar.appendChild(div);
        });
    }

    function closeTab(path, e) {
        if (e) e.stopPropagation();
        openedTabs = openedTabs.filter(p => p !== path);
        if (currentPath === path) {
            currentPath = openedTabs[0] || '';
            if (currentPath) {
                openEbf(currentPath);
            } else {
                document.getElementById('tabBar').style.display = 'none';
                document.getElementById('toolboxBar').style.display = 'none';
                document.getElementById('emptyPlaceholder').style.display = 'flex';
                document.getElementById('virtualScroller').style.display = 'none';
                document.getElementById('anchorFileName').innerText = 'No Table Ope...';
                document.getElementById('slotRibbon').innerHTML = '<div style="font-size: 11px; color: #555; margin-left: 10px;">No EDX Index Attached</div>';
                document.getElementById('stFile').innerText = 'READY';
                ['stSeparator', 'stRec', 'stBof', 'stEof', 'stMode', 'stDel'].forEach(id => {
                    document.getElementById(id).style.display = 'none';
                });
                closeDrawer();
                clearDataBuffer();
                updateCommandEnablement(false);
            }
        } else {
            renderTabs();
        }
    }

    function closeCurrentTab() { if (currentPath) closeTab(currentPath); }

    // =========================================================================
    // 2. EDX Active Slots Ribbon & Index Order Switching
    // =========================================================================
    function renderSlotRibbon(tags) {
        const ribbon = document.getElementById('slotRibbon');
        ribbon.innerHTML = '';

        // 1. Natural Physical Track (Always Present)
        const natCard = document.createElement('div');
        natCard.className = `slot-card ${currentTagId === 0 ? 'active' : ''}`;
        natCard.onclick = () => switchSlot(0);
        natCard.innerHTML = `<div class="slot-card-header"><span>Natural</span><span>★</span></div><div class="slot-card-expr">Physical Track</div>`;
        ribbon.appendChild(natCard);

        // 2. Render ONLY Active / Mounted Tags
        if (tags && tags.length > 0) {
            tags.forEach(tg => {
                const slotNum = tg.slot;
                const card = document.createElement('div');
                card.className = `slot-card ${currentTagId === slotNum ? 'active' : ''}`;
                card.onclick = () => switchSlot(slotNum);
                card.innerHTML = `
                    <div class="slot-card-header"><span>Alt+${slotNum}</span><span>🔑</span></div>
                    <div class="slot-card-expr">${tg.name} (${tg.expression})</div>
                `;
                ribbon.appendChild(card);
            });
        }
    }

    function switchSlot(slot) {
        // Guard: Prevent switching to non-existent tag slots
        if (slot !== 0) {
            const isTagAvailable = currentTags.some(t => t.slot === slot);
            if (!isTagAvailable) return;
        }

        if (slot === currentTagId && slot !== 0) {
            slot = 0; // Toggle back to Natural
        }
        currentTagId = slot;

        // Update active card styling
        document.querySelectorAll('.slot-card').forEach(el => {
            const isMatch = (slot === 0 && el.innerText.includes('Natural')) ||
                            el.innerText.includes(`Alt+${slot}`);
            el.classList.toggle('active', isMatch);
        });

        const modeText = (slot === 0) ? 'Locate' : `Seek [${slot}]`;
        document.getElementById('stMode').innerText = 'MODE: ' + modeText;

        const seekBtn = document.getElementById('btnSeek');
        if (slot === 0) {
            document.getElementById('seekLabel').innerText = '🔍 Locate:';
            document.getElementById('seekLabel').style.color = 'var(--accent-green)';
            seekBtn.innerText = '➔ Locate (F3)';
            seekBtn.classList.remove('seek-mode');
        } else {
            document.getElementById('seekLabel').innerText = `🔍 Seek [${slot}]:`;
            document.getElementById('seekLabel').style.color = 'var(--accent-amber)';
            seekBtn.innerText = '➔ SEEK (F3)';
            seekBtn.classList.add('seek-mode');
        }

        clearDataBuffer();
        selectedRowIdx = 0;
        document.getElementById('gridContainer').scrollTop = 0;
        initVirtualScroller();
    }

    // =========================================================================
    // 3. Virtualized DataGrid Engine
    // =========================================================================
    function renderTableHeaders(fields) {
        let html = `<tr>
            <th class="frozen-act">Actions</th>
            <th class="frozen-num">#</th>
            <th class="frozen-zap">*</th>
        `;
        fields.forEach(f => {
            const fName = isObject(f) ? f.name : f;
            html += `<th>${fName}</th>`;
        });
        html += '</tr>';
        document.getElementById('tableHeader').innerHTML = html;
    }

    function isObject(val) {
        return val !== null && typeof val === 'object';
    }

    function initVirtualScroller() {
        const scroller = document.getElementById('virtualScroller');
        const totalHeight = totalRecords * kRowHeight;
        scroller.style.height = `${Math.max(totalHeight, 100)}px`;
        renderVisibleWindow();
    }

    function onGridScroll() {
        renderVisibleWindow();
    }

    function renderVisibleWindow() {
        if (totalRecords <= 0) return;

        const container = document.getElementById('gridContainer');
        const scrollTop = container.scrollTop;
        const viewportHeight = container.clientHeight || 500;

        let startIdx = Math.floor(scrollTop / kRowHeight) - 5;
        let endIdx = Math.ceil((scrollTop + viewportHeight) / kRowHeight) + 5;

        startIdx = Math.max(0, startIdx);
        endIdx = Math.min(totalRecords - 1, endIdx);

        ensureRowBuffered(startIdx);
        ensureRowBuffered(endIdx);
        triggerDirectionalPreload(startIdx, endIdx);

        const tbody = document.getElementById('tableBody');
        tbody.innerHTML = '';

        const topSpacerHeight = startIdx * kRowHeight;
        if (topSpacerHeight > 0) {
            const trTop = document.createElement('tr');
            trTop.style.height = `${topSpacerHeight}px`;
            trTop.innerHTML = `<td colspan="${currentFields.length + 3}" style="padding:0; border:none; background:transparent;"></td>`;
            tbody.appendChild(trTop);
        }

        for (let i = startIdx; i <= endIdx; i++) {
            const rowData = mapRowCache.get(i);
            const tr = document.createElement('tr');
            tr.style.height = `${kRowHeight}px`;
            tr.setAttribute('data-idx', i);

            if (i === selectedRowIdx) tr.classList.add('selected');
            tr.classList.add(i % 2 === 0 ? 'even-row' : 'odd-row');

            if (rowData) {
                if (rowData.is_deleted) tr.classList.add('is-deleted');
                tr.setAttribute('data-recno', rowData.recno);

                let colsHtml = `
                    <td class="frozen-act">
                        <span style="color:#2ecc71; cursor:pointer;" onclick="commitRow(this)">✔</span>
                        <span style="color:#e74c3c; cursor:pointer; margin-left:8px;" onclick="toggleDel(${rowData.recno})">🗑</span>
                    </td>
                    <td class="frozen-num">${rowData.recno}</td>
                    <td class="frozen-zap">${rowData.is_deleted ? '*' : ''}</td>
                `;

                currentFields.forEach((f, colIdx) => {
                    const fName = isObject(f) ? f.name : f;
                    const isFocused = (i === selectedRowIdx && colIdx === selectedColIdx);
                    const focusedClass = isFocused ? 'cell-focused' : '';
                    colsHtml += `<td class="${focusedClass}" onclick="selectCell(this, ${i}, ${colIdx})" ondblclick="editCell(this)">${rowData.data[fName] || ''}</td>`;
                });

                tr.innerHTML = colsHtml;
            } else {
                tr.innerHTML = `
                    <td class="frozen-act">-</td>
                    <td class="frozen-num">${i + 1}</td>
                    <td class="frozen-zap"></td>
                    <td colspan="${currentFields.length}" style="color:#555;">Loading chunk...</td>
                `;
            }

            tr.onclick = () => selectRowIndex(i);
            tbody.appendChild(tr);
        }

        const bottomSpacerHeight = (totalRecords - 1 - endIdx) * kRowHeight;
        if (bottomSpacerHeight > 0) {
            const trBottom = document.createElement('tr');
            trBottom.style.height = `${bottomSpacerHeight}px`;
            trBottom.innerHTML = `<td colspan="${currentFields.length + 3}" style="padding:0; border:none; background:transparent;"></td>`;
            tbody.appendChild(trBottom);
        }
    }

    function triggerDirectionalPreload(startIdx, endIdx) {
        const currentChunk = Math.floor(startIdx / kChunkSize);
        if ((currentChunk + 1) * kChunkSize < totalRecords) {
            ensureChunkBuffered(currentChunk + 1);
        }
        if (currentChunk > 0) {
            ensureChunkBuffered(currentChunk - 1);
        }
    }

    function ensureRowBuffered(targetIndex) {
        if (targetIndex < 0 || targetIndex >= totalRecords) return;
        if (mapRowCache.has(targetIndex)) return;
        const chunkId = Math.floor(targetIndex / kChunkSize);
        ensureChunkBuffered(chunkId);
    }

    function ensureChunkBuffered(chunkId) {
        if (chunkId < 0 || chunkId * kChunkSize >= totalRecords) return;
        if (setLoadingChunks.has(chunkId)) return;

        const sampleOffset = chunkId * kChunkSize;
        if (mapRowCache.has(sampleOffset)) return;

        setLoadingChunks.add(chunkId);
        postApi('fetch_rows', {
            path: currentPath,
            offset: sampleOffset,
            limit: kChunkSize,
            tag_id: currentTagId
        }, function(res) {
            setLoadingChunks.delete(chunkId);
            if (res.status === 'success') {
                if (mapRowCache.size >= kChunkSize * kMaxCacheChunks) {
                    pruneDistantChunks(chunkId);
                }

                res.rows.forEach((r, idx) => {
                    mapRowCache.set(sampleOffset + idx, r);
                });

                renderVisibleWindow();
            }
        });
    }

    function pruneDistantChunks(activeChunkId) {
        const chunkKeys = new Set();
        for (let idx of mapRowCache.keys()) {
            chunkKeys.add(Math.floor(idx / kChunkSize));
        }

        for (let cid of chunkKeys) {
            if (Math.abs(cid - activeChunkId) > 4) {
                for (let i = 0; i < kChunkSize; i++) {
                    mapRowCache.delete(cid * kChunkSize + i);
                }
            }
        }
    }

    function selectRowIndex(rowIdx) {
        if (rowIdx < 0 || rowIdx >= totalRecords) return;
        selectedRowIdx = rowIdx;

        const rowData = mapRowCache.get(rowIdx);
        const recNo = rowData ? rowData.recno : (rowIdx + 1);

        document.getElementById('stRec').innerText = `REC: ${rowIdx + 1} / ${totalRecords}`;
        document.getElementById('stBof').classList.toggle('active', rowIdx === 0);
        document.getElementById('stEof').classList.toggle('active', rowIdx === totalRecords - 1);

        renderVisibleWindow();
    }

    function selectCell(td, rowIdx, colIdx) {
        selectedRowIdx = rowIdx;
        selectedColIdx = colIdx;
        renderVisibleWindow();
    }

    function ensureRowVisible(rowIdx) {
        const container = document.getElementById('gridContainer');
        const targetY = rowIdx * kRowHeight;
        const currentY = container.scrollTop;
        const viewportHeight = container.clientHeight;

        if (targetY < currentY) {
            container.scrollTop = targetY;
        } else if (targetY + kRowHeight > currentY + viewportHeight) {
            container.scrollTop = targetY + kRowHeight - viewportHeight;
        }
    }

    function editCell(td) {
        if (td.querySelector('input')) return;
        const oldVal = td.innerText.trim();
        const input = document.createElement('input');
        input.value = oldVal;
        input.style.cssText = 'width:100%; height:100%; background:#000; border:2px solid var(--accent-amber); color:#fff; font-family:var(--font-mono); outline:none; font-weight:700;';
        td.innerHTML = '';
        td.appendChild(input);
        input.focus();
        input.select();

        input.onblur = () => td.innerText = input.value.trim();
        input.onkeydown = (e) => {
            if (e.key === 'Enter') input.blur();
            if (e.key === 'Escape') td.innerText = oldVal;
        };
    }

    function commitRow(btn) {
        const tr = btn.closest('tr');
        const recno = tr.getAttribute('data-recno');
        const idx = parseInt(tr.getAttribute('data-idx'));
        const vals = [];
        tr.querySelectorAll('td:not(.frozen-act):not(.frozen-num):not(.frozen-zap)').forEach(td => vals.push(td.innerText.trim()));

        postApi('update_cell', { path: currentPath, row_id: recno, csv_data: vals.join(',') }, function(res) {
            if (res.status === 'success') {
                const rowData = mapRowCache.get(idx);
                if (rowData) {
                    currentFields.forEach((f, i) => {
                        const fName = isObject(f) ? f.name : f;
                        rowData.data[fName] = vals[i];
                    });
                }
                tr.style.background = 'rgba(46, 204, 113, 0.3)';
                setTimeout(() => tr.style.background = '', 400);
            } else {
                alert('Failed to save row: ' + (res.message || 'Unknown error'));
            }
        });
    }

    function toggleDel(recno) {
        postApi('toggle_delete', { path: currentPath, row_id: recno }, function(res) {
            if (res.status === 'success') {
                document.getElementById('stDel').innerText = `DEL: ${res.deleted_count}`;
                clearDataBuffer();
                renderVisibleWindow();
            } else {
                alert('Toggle delete mark failed: ' + (res.message || 'Unknown error'));
            }
        });
    }

    function toggleDeleteActive() {
        const rowData = mapRowCache.get(selectedRowIdx);
        if (rowData) toggleDel(rowData.recno);
    }

    function saveCurrentTab() {
        const tr = document.querySelector(`tr[data-idx="${selectedRowIdx}"]`);
        if (tr) commitRow(tr.querySelector('.frozen-act span'));
    }

    function saveAllTabs() { alert('All Tabs Committed.'); }

    // =========================================================================
    // 4. Smart Seek / Locate Execution Logic
    // =========================================================================
    function activateLocate() { document.getElementById('seekInput').focus(); }

    function executeSeek() {
        if (!currentPath) return;
        const input = document.getElementById('seekInput');
        const keyword = input.value.trim();
        if (!keyword) return;

        // 1. Natural Track: Execute Locate mode
        if (currentTagId === 0) {
            const fName = (currentFields.length > 0 && selectedColIdx < currentFields.length)
                ? (isObject(currentFields[selectedColIdx]) ? currentFields[selectedColIdx].name : currentFields[selectedColIdx])
                : (isObject(currentFields[0]) ? currentFields[0].name : currentFields[0]);

            postApi('seek_locate', {
                path: currentPath,
                mode: 'locate',
                field_name: fName,
                key: keyword,
                start_rec: selectedRowIdx + 2 // Start scanning from subsequent record
            }, function(res) {
                if (res && res.status === 'success') {
                    if (res.found && res.recno > 0) {
                        document.getElementById('stEof').classList.remove('active');
                        jumpToTargetRow(res.recno - 1);
                    } else {
                        document.getElementById('stEof').classList.add('active');
                        showToast('Locate EOF', `Locate reached EOF for [${keyword}] on Field [${fName}].`, 'warning');
                    }
                } else {
                    showToast('Search Error', (res && res.message) ? res.message : 'Unknown server error', 'error');
                }
            });
            return;
        }

        // 2. EDX Track (Alt+1 ~ Alt+8): Execute Seek mode
        const activeTag = currentTags.find(t => t.slot === currentTagId);
        if (!activeTag) {
            showToast('No Active Tag', `Tag slot [${currentTagId}] is empty or unattached.`, 'warning');
            return;
        }

        postApi('seek_locate', {
            path: currentPath,
            mode: 'seek',
            tag_name: activeTag.name,
            tag_id: currentTagId,
            key: keyword
        }, function(res) {
            if (res && res.status === 'success') {
                if (res.found && res.recno > 0) {
                    document.getElementById('stEof').classList.remove('active');

                    // C-Core ez_db_recno returns 1-based node sequence index on the active tag track
                    const targetIdx = res.recno - 1;
                    jumpToTargetRow(targetIdx);
                } else {
                    if (res.eof) {
                        document.getElementById('stEof').classList.add('active');
                        showToast('EOF Reached', `Seek reached EOF for [${keyword}] on Tag [${activeTag.name}].`, 'warning');
                    } else {
                        showToast('Not Found', `Seek Not Found: [${keyword}] (Tag: ${activeTag.name})`, 'info');
                    }
                }
            } else {
                showToast('Search Error', (res && res.message) ? res.message : 'Unknown server error', 'error');
            }
        });
    }

    function jumpToTargetRow(targetIdx) {
        if (targetIdx < 0) targetIdx = 0;
        if (targetIdx >= totalRecords) targetIdx = Math.max(0, totalRecords - 1);

        // 1. Update selection state and status bar indicators
        selectRowIndex(targetIdx);

        // 2. Center the target row within viewport scroll area
        const container = document.getElementById('gridContainer');
        if (container) {
            const viewportHeight = container.clientHeight || 500;
            const targetY = Math.max(0, (targetIdx * kRowHeight) - (viewportHeight / 2) + (kRowHeight / 2));
            container.scrollTop = targetY;
        }

        // 3. Ensure target buffer chunk is loaded and render the window
        ensureRowBuffered(targetIdx);
        renderVisibleWindow();
    }

    // =========================================================================
    // 5. Toolchain Drawer Control & Module Initialization
    // =========================================================================
    function toggleDrawer(tool, isNew = false) {
        const drawer = document.getElementById('toolchainDrawer');
        if (activeTool === tool && !isNew) {
            closeDrawer();
            return;
        }
        activeTool = tool;
        
        const tbBar = document.getElementById('toolboxBar');
        if (tbBar) tbBar.style.display = 'flex';

        drawer.classList.add('open');
        drawer.style.display = 'flex';
        
        const pSchema = document.getElementById('panelSchema');
        const pRelation = document.getElementById('panelRelation');
        
        if (pSchema) pSchema.style.display = (tool === 'schema') ? 'flex' : 'none';
        if (pRelation) pRelation.style.display = (tool === 'relation') ? 'flex' : 'none';

        document.getElementById('btnSchemaToggle').classList.toggle('active', tool === 'schema');
        document.getElementById('btnRelToggle').classList.toggle('active', tool === 'relation');

        if (tool === 'schema' && typeof initSchemaUI === 'function') initSchemaUI(isNew);
        if (tool === 'relation' && typeof initRelationUI === 'function') initRelationUI();
    }

    function updateIndexSlotMenu() {
        const container = document.getElementById('menuIndexSlotContainer');
        if (!container) return;
        container.innerHTML = '';

        for (let i = 1; i <= 8; i++) {
            const tg = currentTags.find(t => t.slot === i);
            const isAvailable = Boolean(tg);
            const isSelected = (currentTagId === i);
            
            const div = document.createElement('div');
            div.className = 'dropdown-item';
            
            if (!isAvailable) {
                div.style.opacity = '0.35';
                div.style.cursor = 'not-allowed';
                div.innerHTML = `<span>Slot [${i}] (Empty)</span><span class="item-key">Alt+${i}</span>`;
            } else {
                div.onclick = () => switchSlot(i);
                const checkMark = isSelected ? '<span style="color:var(--accent-amber); margin-right:6px;">✔</span>' : '';
                div.innerHTML = `<span>${checkMark}${tg.name} [Slot ${i}]</span><span class="item-key">Alt+${i}</span>`;
            }
            container.appendChild(div);
        }
    }

    function closeDrawer() {
        activeTool = null;
        const drawer = document.getElementById('toolchainDrawer');
        if (drawer) {
            drawer.classList.remove('open');
            drawer.style.display = 'none';
        }

        const btnSchema = document.getElementById('btnSchemaToggle');
        const btnRel = document.getElementById('btnRelToggle');
        if (btnSchema) btnSchema.classList.remove('active');
        if (btnRel) btnRel.classList.remove('active');

        const pSchema = document.getElementById('panelSchema');
        const pRelation = document.getElementById('panelRelation');
        if (pSchema) pSchema.style.display = 'none';
        if (pRelation) pRelation.style.display = 'none';

        const grid = document.getElementById('gridContainer');
        if (grid) grid.focus();
    }

    // =========================================================================
    // 6. Schema Designer Client Operations
    // =========================================================================
    function handleNewSchema() { toggleDrawer('schema', true); }

    function initSchemaUI(isNew) {
        const tbody = document.querySelector('#tblSchemaFields tbody');
        const idxBody = document.querySelector('#tblSchemaIndexes tbody');
        tbody.innerHTML = '';
        idxBody.innerHTML = '';

        if (isNew) {
            document.getElementById('lblSchemaTitle').innerText = 'Create New EBF Database Schema';
            document.getElementById('txtSchemaEbfPath').value = '';
            document.getElementById('btnSaveSchemaText').innerText = 'Generate & Create EBF';
            addSchemaFieldRow('ID', 'I', 4);
            addSchemaFieldRow('NAME', 'C', 36);
            addSchemaIndexRow('TAG_ID', 'ID');
        } else {
            document.getElementById('lblSchemaTitle').innerText = 'Modify Existing EBF Schema (ez_dbalter)';
            document.getElementById('txtSchemaEbfPath').value = currentPath;
            document.getElementById('btnSaveSchemaText').innerText = 'Save EBF';
            if (currentFields.length > 0) {
                currentFields.forEach(f => {
                    const fName = isObject(f) ? f.name : f;
                    const fType = isObject(f) ? f.type : 'C';
                    const fLen = isObject(f) ? f.len : 10;
                    addSchemaFieldRow(fName, fType, fLen);
                });
            } else {
                addSchemaFieldRow('date', 'C', 10);
                addSchemaFieldRow('code', 'C', 12);
                addSchemaFieldRow('name', 'C', 36);
            }
            addSchemaIndexRow('idx_code', 'code');
            addSchemaIndexRow('idx_date', 'date');
        }
    }

    function addSchemaFieldRow(name = 'field', type = 'C', len = 10) {
        const tbody = document.querySelector('#tblSchemaFields tbody');
        const idx = tbody.children.length + 1;
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>${idx}.</td>
            <td><input type="text" class="sf-name" value="${name}" style="width:100%; background:#000; color:#fff; border:1px solid #444; padding:3px;" /></td>
            <td>
                <select class="sf-type" style="background:#000; color:#fff; border:1px solid #444; width:100%; padding:3px;">
                    <option value="C" ${type==='C'?'selected':''}>C (Text)</option>
                    <option value="N" ${type==='N'?'selected':''}>N (Numeric)</option>
                    <option value="I" ${type==='I'?'selected':''}>I (Integer)</option>
                    <option value="D" ${type==='D'?'selected':''}>D (Date)</option>
                    <option value="L" ${type==='L'?'selected':''}>L (Logical)</option>
                    <option value="B" ${type==='B'?'selected':''}>B (BLOB)</option>
                </select>
            </td>
            <td><input type="number" class="sf-len" value="${len}" style="width:100%; background:#000; color:#fff; border:1px solid #444; padding:3px;" /></td>
            <td style="text-align:center;"><span style="color:red; cursor:pointer;" onclick="this.closest('tr').remove()">🗑</span></td>
        `;
        tbody.appendChild(tr);
    }

    function addSchemaIndexRow(tag = 'idx_tag', expr = 'field') {
        const tbody = document.querySelector('#tblSchemaIndexes tbody');
        const idx = tbody.children.length + 1;
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td>Tag ${idx}.</td>
            <td><input type="text" class="si-tag" value="${tag}" style="width:100%; background:#000; color:#fff; border:1px solid #444; padding:3px;" /></td>
            <td><input type="text" class="si-expr" value="${expr}" style="width:100%; background:#000; color:#fff; border:1px solid #444; padding:3px;" /></td>
            <td style="text-align:center;"><span style="color:red; cursor:pointer;" onclick="this.closest('tr').remove()">🗑️</span></td>
        `;
        tbody.appendChild(tr);
    }

    function loadSchemaFromFile(path) {
        document.getElementById('txtSchemaEbfPath').value = path;
        postApi('open', { path: path }, function(res) {
            if (res.status === 'success') {
                const tbody = document.querySelector('#tblSchemaFields tbody');
                tbody.innerHTML = '';
                res.fields.forEach(f => {
                    const fName = isObject(f) ? f.name : f;
                    const fType = isObject(f) ? f.type : 'C';
                    const fLen = isObject(f) ? f.len : 10;
                    addSchemaFieldRow(fName, fType, fLen);
                });
            }
        });
    }

    function executeSaveSchema() {
        const path = document.getElementById('txtSchemaEbfPath').value.trim();
        if (!path) return alert('Please specify file path');
        const fields = [];
        document.querySelectorAll('#tblSchemaFields tbody tr').forEach(tr => {
            fields.push({
                name: tr.querySelector('.sf-name').value.trim(),
                type: tr.querySelector('.sf-type').value,
                len: tr.querySelector('.sf-len').value,
                dec: 0
            });
        });
        const indexes = [];
        document.querySelectorAll('#tblSchemaIndexes tbody tr').forEach(tr => {
            indexes.push({
                name: tr.querySelector('.si-tag').value.trim(),
                expr: tr.querySelector('.si-expr').value.trim(),
                unique: false
            });
        });

        postApi('create_table', { new_path: path, fields: JSON.stringify(fields), indexes: JSON.stringify(indexes) }, function(res) {
            if (res.status === 'success') {
                alert('⚡ EBF table schema and indexes created successfully!');
                closeDrawer();
                openEbf(res.path);
            } else {
                alert('Failed to create table: ' + (res.message || 'Unknown error'));
            }
        });
    }

    // =========================================================================
    // 7. Server File Explorer Modal
    // =========================================================================
    let selectedExpFile = '';
    let expCallback = null;

    function openFileExplorer(dir = '', cb = null) {
        expCallback = cb;
        postApi('browse_dir', { dir: dir }, function(res) {
            if (res.status === 'success') {
                document.getElementById('expCurrentPath').value = res.current;
                const list = document.getElementById('explorerList');
                list.innerHTML = '';

                res.items.forEach(it => {
                    const icon = it.is_dir ? '📁' : '📄';
                    const div = document.createElement('div');
                    div.className = 'explorer-row';
                    div.innerHTML = `<span>${icon}</span><span style="flex:1;">${it.name}</span>`;

                    div.onclick = () => {
                        if (it.is_dir) {
                            if (it.is_parent) {
                                explorerUp();
                            } else {
                                openFileExplorer(it.path, expCallback);
                            }
                        } else {
                            if (!it.name.toLowerCase().endsWith('.ebf')) return;

                            document.querySelectorAll('.explorer-row').forEach(r => r.classList.remove('selected'));
                            div.classList.add('selected');
                            selectedExpFile = it.path;
                            document.getElementById('btnExpConfirm').disabled = false;
                        }
                    };
                    list.appendChild(div);
                });

                openModal('#fileExplorerModal');
            } else {
                alert('Browse directory failed: ' + (res.message || 'Unknown error'));
            }
        });
    }

    function explorerUp() {
        const cur = document.getElementById('expCurrentPath').value.trim();
        const lastSep = Math.max(cur.lastIndexOf('/'), cur.lastIndexOf('\\'));

        if (lastSep > 0) {
            let parent = cur.substring(0, lastSep);
            if (parent.length === 2 && parent.charAt(1) === ':') {
                parent += '\\';
            }
            openFileExplorer(parent, expCallback);
        } else if (lastSep === 0) {
            openFileExplorer('/', expCallback);
        }
    }

    function confirmOpenExplorer() {
        closeModal('#fileExplorerModal');
        if (selectedExpFile) {
            if (typeof expCallback === 'function') {
                expCallback(selectedExpFile);
                expCallback = null;
            } else {
                openEbf(selectedExpFile);
            }
        }
    }

    function openModal(id) { document.querySelector(id).style.display = 'flex'; }
    function closeModal(id) { document.querySelector(id).style.display = 'none'; }

    function executeGoTo() {
        const val = parseInt(document.getElementById('inputGoTo').value);
        if (val >= 1 && val <= totalRecords) {
            closeModal('#goToRowModal');
            const targetIdx = val - 1;
            selectRowIndex(targetIdx);
            ensureRowVisible(targetIdx);
        }
    }

    // =========================================================================
    // 8. Global Keyboard Shortcuts Listener
    // =========================================================================
    window.addEventListener('keydown', (e) => {
        if (!isFfiAvailable) {
            if (e.key !== 'F5' && !(e.ctrlKey && e.key.toLowerCase() === 'r')) {
                e.preventDefault();
                e.stopPropagation();
            }
            return;
        }

        if (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'SELECT') return;
        if (activeTool !== null) return;

        const viewportHeight = document.getElementById('gridContainer').clientHeight || 500;
        const pageSize = Math.max(1, Math.floor(viewportHeight / kRowHeight) - 1);

        if (e.key === 'ArrowDown') {
            e.preventDefault();
            if (selectedRowIdx < totalRecords - 1) {
                selectRowIndex(selectedRowIdx + 1);
                ensureRowVisible(selectedRowIdx);
            } else {
                document.getElementById('stEof').classList.add('active');
                document.getElementById('stBof').classList.remove('active');
            }
        } else if (e.key === 'ArrowUp') {
            e.preventDefault();
            if (selectedRowIdx > 0) {
                selectRowIndex(selectedRowIdx - 1);
                ensureRowVisible(selectedRowIdx);
            } else {
                document.getElementById('stBof').classList.add('active');
                document.getElementById('stEof').classList.remove('active');
            }
        } else if (e.key === 'PageDown') {
            e.preventDefault();
            const target = Math.min(totalRecords - 1, selectedRowIdx + pageSize);
            selectRowIndex(target);
            ensureRowVisible(target);
        } else if (e.key === 'PageUp') {
            e.preventDefault();
            const target = Math.max(0, selectedRowIdx - pageSize);
            selectRowIndex(target);
            ensureRowVisible(target);
        } else if (e.key === 'Home') {
            e.preventDefault();
            selectRowIndex(0);
            ensureRowVisible(0);
        } else if (e.key === 'End') {
            e.preventDefault();
            selectRowIndex(totalRecords - 1);
            ensureRowVisible(totalRecords - 1);
        } else if (e.key === 'ArrowRight') {
            if (selectedColIdx < currentFields.length - 1) {
                selectedColIdx++;
                renderVisibleWindow();
            }
        } else if (e.key === 'ArrowLeft') {
            if (selectedColIdx > 0) {
                selectedColIdx--;
                renderVisibleWindow();
            }
        } else if (e.key === 'Delete') {
            toggleDeleteActive();
        } else if (e.ctrlKey && e.key.toLowerCase() === 'o') {
            e.preventDefault(); openFileExplorer();
        } else if (e.ctrlKey && e.key.toLowerCase() === 'n') {
            e.preventDefault(); handleNewSchema();
        } else if (e.ctrlKey && e.key.toLowerCase() === 's') {
            e.preventDefault(); saveCurrentTab();
        } else if (e.ctrlKey && e.key.toLowerCase() === 'g') {
            e.preventDefault(); openModal('#goToRowModal');
        } else if (e.ctrlKey && e.key.toLowerCase() === 'f') {
            e.preventDefault(); activateLocate();
        } else if (e.altKey && e.key >= '1' && e.key <= '8') {
            e.preventDefault();
            switchSlot(parseInt(e.key));
        }
    });

    function updateCommandEnablement(hasActiveEbf) {
        document.querySelectorAll('.menu-requires-ebf').forEach(el => {
            el.classList.toggle('disabled', !hasActiveEbf);
        });
        updateIndexSlotMenu();
    }

    const rawToggleDrawer = toggleDrawer;
    toggleDrawer = function(tool, isNew = false) {
        if (tool === 'relation' && (!currentPath || openedTabs.length === 0)) {
            alert('Please open at least one EBF table before entering Relation Studio!');
            return;
        }
        rawToggleDrawer(tool, isNew);
    };

    window.addEventListener('load', () => {
        console.log('ezDBUtility Workstation Initialized.');
        updateCommandEnablement(false);
    });

    const seekInputEl = document.getElementById('seekInput');
    if (seekInputEl) {
        seekInputEl.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === 'F3') {
                e.preventDefault();
                e.stopPropagation();
                executeSeek();
            }
        });
    }
    </script>
</body>
</html>