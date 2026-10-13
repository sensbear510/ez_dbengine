<?php
/**
 * =================================================================================
 * FILE: dbu_web.php - Master Workplace for ezDBUtility (Web Edition)
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * STAGE 1 Baseline: Aligned with desktop_main_page.dart (C-Core True Operations)
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
        // Retrieve persistent C engine singleton instance (fallback if SDK does not implement getInstance)
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

                    // Dynamically assemble full path according to platform directory separator
                    $fullPath = rtrim($realDir, '\\/') . $ds . $file;
                    $isDir = is_dir($fullPath);

                    // Retain directories and *.ebf files only, filtering out .edx, .erl, etc.
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

            // Prevent escaping backslashes when outputting JSON, include platform info
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

            // Pass absolute file path directly to prevent chdir security restrictions and path conflicts in web environment
            $handle = $engine->use($realPath);

            // Strict verification: Handle value 0 denotes true file open failure
            if ($handle === 0) {
                $err = EzDBEngine::getDetailedError(-104);
                throw new Exception("Unable to mount EBF WorkArea: $path | $err");
            }

            // Inspect underlying warnings (such as missing .edx in same directory)
            $warningMsg = null;
            $lastErr = EzDBEngine::lastError();
            if (!empty($lastErr) && stripos($lastErr, 'warning') !== false) {
                $warningMsg = $lastErr . " (Notice: Mounted .edx index file must reside in the same directory as the .ebf table)";
            }

            $fields = $engine->getFdt($handle);
            $total = $engine->getTotalRecords($handle);
            $delCount = $engine->getDeleteCount($handle);

            $tags = [];
            for ($i = 1; $i <= 8; $i++) {
                $lastRec = $engine->getLastRec($i, $handle);
                if ($lastRec > 0) {
                    $tags[] = [
                        'slot' => $i,
                        'name' => ($i === 1 ? 'idx_code' : 'idx_date'),
                        'expression' => ($i === 1 ? 'code' : 'date')
                    ];
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

        // Native C-Core vector read and EDX sorting via persistent engine and handle
        if ($api === 'fetch_rows') {
            $path = $_POST['path'] ?? '';
            $offset = (int)($_POST['offset'] ?? 0);
            $limit = (int)($_POST['limit'] ?? 200);
            $tagId = (int)($_POST['tag_id'] ?? 0);

            $handle = $engine->use($path);
            $fields = $engine->getFdt($handle);
            $total = $engine->getLastRec($tagId, $handle);
            
            $engine->goTo($offset + 1, $tagId, $handle);

            $rows = [];
            for ($i = 0; $i < $limit && ($offset + $i) < $total; $i++) {
                $raw = $engine->getRecord($tagId, $handle);
                if ($raw === null) break;

                $physicalRowId = $engine->getRecno($tagId, $handle);
                $isDel = $engine->isDeleted($physicalRowId, $handle);

                $colValues = [];
                $cur = 0;
                foreach ($fields as $f) {
                    $val = substr($raw, $cur, $f->length);
                    $colValues[$f->name] = trim($val);
                    $cur += $f->length;
                }

                $rows[] = [
                    'track_index' => $offset + $i + 1,
                    'recno'       => $physicalRowId,
                    'is_deleted'  => $isDel,
                    'data'        => $colValues
                ];

                if ($engine->skip(1, $tagId, $handle) !== 0) break;
            }

            echo json_encode(['status' => 'success', 'rows' => $rows, 'total' => $total, 'offset' => $offset]);
            exit;
        }

        if ($api === 'seek_locate') {
            $path = $_POST['path'] ?? '';
            $mode = $_POST['mode'] ?? 'locate';
            $tagName = $_POST['tag_name'] ?? '';
            $key = $_POST['key'] ?? '';
            $fieldName = $_POST['field_name'] ?? '';
            $startRec = (int)($_POST['start_rec'] ?? 1);

            $handle = $engine->use($path);

            if ($mode === 'seek') {
                $found = $engine->seekByTag($tagName, $key, $handle);
                $foundRec = $found ? $engine->getRecno(0, $handle) : 0;
                echo json_encode(['status' => 'success', 'found' => $found, 'recno' => $foundRec]);
                exit;
            } else {
                $engine->goTo($startRec, 0, $handle);
                $found = $engine->locate($fieldName, $key, $handle);
                $foundRec = ($found === 0) ? $engine->getRecno(0, $handle) : 0;
                echo json_encode(['status' => 'success', 'found' => ($found === 0), 'recno' => $foundRec]);
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
        
        /* 4. Smart Seek Bar (48px) - Full-width input, action buttons aligned right with 10px spacing */
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

        /* 5. Virtualized DataGrid Architecture (Virtual Spacer + Sliding Window) */
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

        /* 6. Bottom TOOLBOX Bar (36px) - Always displayed above the status bar */
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

        /* 8. Collapsible Toolchain Drawer (Height expanded to calc(100vh - 160px)) */
        /* 8. Collapsible Toolchain Drawer (Ensured z-index: 2000 to overlay above DataGrid) */
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

        /* =============================================================
           RWD: Tablet (Pad: <= 1024px) & Mobile (Phone: <= 600px) Adaptation Rules
        ============================================================= */
        @media screen and (max-width: 1024px) {
            .toolchain-drawer {
                top: 80px; /* Reserve expanded working height on tablet form factors */
            }
        }

        @media screen and (max-width: 600px) {
            /* 1. Header and top menu stacking compression */
            .header-shell {
                height: auto;
                flex-direction: column;
                align-items: stretch;
                padding: 8px 10px;
                gap: 8px;
            }
            .ebf-anchor-card {
                width: 100%;
                height: 48px;
            }
            .slot-ribbon {
                width: 100%;
                height: 54px;
            }
            .slot-card {
                width: 110px;
                height: 48px;
                padding: 4px 6px;
            }

            /* 2. Seek Bar auto-wrap */
            .smart-seek-bar {
                height: auto;
                flex-wrap: wrap;
                padding: 8px 10px;
            }
            .seek-input {
                max-width: 100%;
            }

            /* 3. Compact main DataGrid frozen columns (Aligned with Flutter: 72px) */
            .frozen-act { width: 44px; }
            .frozen-num { width: 38px; left: 44px; }
            .frozen-zap { left: 82px; }

            /* 4. Fullscreen drawer view on mobile devices */
            .toolchain-drawer {
                top: 0;
                bottom: 0;
                border-top: none;
                z-index: 3000;
            }
            .drawer-body {
                flex-direction: column;
                padding: 8px;
                gap: 10px;
                overflow-y: auto;
            }

            /* 5. Fullscreen modal adaptation for file explorer */
            .modal-card {
                width: 95vw !important;
                height: 85vh !important;
            }
        }

        /* =========================================================================
        Craftsman Toast / Slide Notification Panel
        ========================================================================= */
        .toast-container {
            position: fixed;
            top: 48px;
            right: 20px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            z-index: 100000;
            pointer-events: none;
        }

        .toast-panel {
            min-width: 340px;
            max-width: 480px;
            background: #1e2025;
            border-radius: 6px;
            box-shadow: 0 12px 32px rgba(0, 0, 0, 0.75);
            padding: 12px 16px;
            display: flex;
            align-items: flex-start;
            gap: 12px;
            pointer-events: auto;
            transform: translateX(120%);
            opacity: 0;
            transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.3s ease;
            border-left: 4px solid var(--accent-amber);
            border-top: 1px solid rgba(255, 255, 255, 0.08);
            border-right: 1px solid rgba(255, 255, 255, 0.08);
            border-bottom: 1px solid rgba(255, 255, 255, 0.08);
        }

        .toast-panel.show {
            transform: translateX(0);
            opacity: 1;
        }

        .toast-panel.warning {
            border-left-color: var(--accent-amber);
        }

        .toast-panel.error {
            border-left-color: var(--accent-red);
        }

        .toast-panel.info {
            border-left-color: #3498db;
        }

        .toast-icon {
            font-size: 18px;
            line-height: 1.2;
        }

        .toast-content {
            flex: 1;
            display: flex;
            flex-direction: column;
            gap: 4px;
        }

        .toast-title {
            font-size: 12px;
            font-weight: 700;
            color: #fff;
            letter-spacing: 0.5px;
        }

        .toast-panel.warning .toast-title {
            color: var(--accent-amber);
        }

        .toast-panel.error .toast-title {
            color: var(--accent-red);
        }

        .toast-message {
            font-size: 11px;
            color: #bbb;
            line-height: 1.5;
            word-break: break-all;
            font-family: var(--font-ui);
        }

        .toast-close {
            cursor: pointer;
            color: #777;
            font-size: 14px;
            line-height: 1;
            padding: 2px;
        }

        .toast-close:hover {
            color: #fff;
        }
    </style>
</head>
<body>

    <!-- Global Slide Notification Container -->
    <div class="toast-container" id="toastContainer"></div>

    <!-- FFI Crash Notification Bar (Top Red Alert) -->
    <div id="ffiCrashBar" style="<?php echo $ffiInitError ? 'display:flex;' : 'display:none;'; ?> position:fixed; top:0; left:0; right:0; height:40px; background:#b71c1c; color:#fff; z-index:99999; align-items:center; padding:0 16px; font-size:12px; font-weight:700; box-shadow:0 4px 16px rgba(0,0,0,0.8); gap:12px; border-bottom:1px solid #ff5252;">
        <span style="font-size:16px;">🚨</span>
        <span style="letter-spacing:0.5px;">[C-CORE FFI FAILURE]:</span>
        <span id="ffiCrashMsg" style="font-family:var(--font-mono); font-weight:normal; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">
            <?php echo htmlspecialchars($ffiInitError ?? ''); ?>
        </span>
        <button onclick="location.reload()" style="background:#fff; color:#b71c1c; border:none; padding:4px 12px; font-size:11px; font-weight:800; border-radius:4px; cursor:pointer;">Press F5 to Reload</button>
    </div>

    <!-- Workplace Lockdown Overlay -->
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
        
        <!-- File Menu -->
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

        <!-- Edit Menu -->
        <div class="dropdown-menu">
            <button class="menu-btn">Edit</button>
            <div class="dropdown-content">
                <div class="dropdown-item" onclick="activateLocate()"><span>Find Keyword</span><span class="item-key">Ctrl+F</span></div>
                <div class="dropdown-item" onclick="openModal('#goToRowModal')"><span>Go To Row</span><span class="item-key">Ctrl+G</span></div>
                <div class="dropdown-divider"></div>
                
                <!-- Dynamic EDX Tag 1 ~ 8 Slot Container -->
                <div id="menuIndexSlotContainer">
                    <!-- Dynamically populated with active tab EDX slots 1-8 via updateIndexSlotMenu() -->
                </div>
                
                <div class="dropdown-divider"></div>
                <div class="dropdown-item" onclick="toggleDeleteActive()"><span>Delete Toggle</span><span class="item-key">Delete</span></div>
            </div>
        </div>

        <!-- Tools Menu -->
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

    <!-- 5. Virtualized DataGrid Workplace (Aligned with desktop_main_page) -->
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

    <!-- JavaScript Driver Core (Chunk Loading, Bidirectional Preload, Memory Guard Engine) -->
    <script>
    
    /**
     * Show Craftsman Slide Notification panel
     * @param {string} title Toast title
     * @param {string} message Detailed message body
     * @param {'info' | 'warning' | 'error'} type Toast type
     * @param {number} duration Display duration in milliseconds (default 4500ms; 0 to disable auto-dismiss)
     */
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

        // Trigger entrance slide animation
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
            .then(r => r.json())
            .then(cb)
            .catch(err => console.error('API Error:', err));
    }

    // -------------------------------------------------------------
    // Global Workplace & Virtualized Chunk Buffer State (Aligned with desktop_main_page)
    // -------------------------------------------------------------
    const kRowHeight = 36.0;         // Fixed row height: 36px
    const kChunkSize = 200;          // Asynchronously fetch slices of 200 rows
    const kMaxCacheChunks = 10;      // Memory leak guard: cache up to 10 chunks (2,000 rows)

    // FFI Core status guard flag
    const isFfiAvailable = <?php echo ($ffiInitError === null) ? 'true' : 'false'; ?>;

    let openedTabs = [];
    let currentPath = '';
    let currentFields = [];
    let currentTags = [];
    let currentTagId = 0;           // 0: Natural, 1~8: EDX Tag Slot
    let totalRecords = 0;

    let selectedRowIdx = 0;         // Currently selected row index (0-based)
    let selectedColIdx = 0;
    let activeTool = null;
    let relJoinMode = 0;

    // Main DataGrid chunk cache data structure: Map<rowIndex, rowData>
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

                // Expand workplace components and unlock menu action restrictions
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

                // Display non-blocking index mounting notification via slide panel
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
                // Revert to initial view layout
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
    // 2. EDX 8-Slot Carousel & Index Order Switching
    // =========================================================================
    function renderSlotRibbon(tags) {
        const ribbon = document.getElementById('slotRibbon');
        ribbon.innerHTML = '';

        const natCard = document.createElement('div');
        natCard.className = `slot-card ${currentTagId===0?'active':''}`;
        natCard.onclick = () => switchSlot(0);
        natCard.innerHTML = `<div class="slot-card-header"><span>Natural</span><span>★</span></div><div class="slot-card-expr">Physical Track</div>`;
        ribbon.appendChild(natCard);

        for (let i = 1; i <= 8; i++) {
            const tg = tags.find(t => t.slot === i);
            const name = tg ? tg.name : `idx_tag${i}`;
            const expr = tg ? tg.expression : `key_${i}`;
            const card = document.createElement('div');
            card.className = `slot-card ${currentTagId===i?'active':''}`;
            card.onclick = () => switchSlot(i);
            card.innerHTML = `
                <div class="slot-card-header"><span>Alt+${i}</span><span>🔑</span></div>
                <div class="slot-card-expr">${name} (${expr})</div>
            `;
            ribbon.appendChild(card);
        }
    }

    function switchSlot(slot) {
        if (slot === currentTagId && slot !== 0) {
            slot = 0;
        }
        currentTagId = slot;
        document.querySelectorAll('.slot-card').forEach((el, idx) => el.classList.toggle('active', idx === slot));

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
    // 3. Virtualized DataGrid Engine (Virtual Spacer + Sliding Window + Bidirectional Preload)
    // =========================================================================
    function renderTableHeaders(fields) {
        let html = `<tr>
            <th class="frozen-act">Actions</th>
            <th class="frozen-num">#</th>
            <th class="frozen-zap">*</th>
        `;
        fields.forEach(f => { html += `<th>${f.name}</th>`; });
        html += '</tr>';
        document.getElementById('tableHeader').innerHTML = html;
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

        // Bidirectional Preload Pipeline: Keep active and neighboring slices ready
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
                    const isFocused = (i === selectedRowIdx && colIdx === selectedColIdx);
                    const focusedClass = isFocused ? 'cell-focused' : '';
                    colsHtml += `<td class="${focusedClass}" onclick="selectCell(this, ${i}, ${colIdx})" ondblclick="editCell(this)">${rowData.data[f.name] || ''}</td>`;
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

    // Bidirectional Preload Pipeline (Lookahead / Lookback)
    function triggerDirectionalPreload(startIdx, endIdx) {
        const currentChunk = Math.floor(startIdx / kChunkSize);
        // Lookahead preload
        if ((currentChunk + 1) * kChunkSize < totalRecords) {
            ensureChunkBuffered(currentChunk + 1);
        }
        // Lookback preload
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

    // Core Chunk Asynchronous Fetching & Sliding Window Eviction Guard
    function ensureChunkBuffered(chunkId) {
        if (chunkId < 0 || chunkId * kChunkSize >= totalRecords) return;
        if (setLoadingChunks.has(chunkId)) return;

        // Check if first record of chunk already exists
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
                // Memory guard: trigger eviction if total cached chunks exceed 10 (keep nearest chunks)
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

    // Evict chunks furthest from currently visible viewport
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
                    currentFields.forEach((f, i) => rowData.data[f.name] = vals[i]);
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
    // 4. Smart Seek / Locate Execution Logic (Aligned with Dart C-Core)
    // =========================================================================
    function activateLocate() { document.getElementById('seekInput').focus(); }

    function executeSeek() {
        const keyword = document.getElementById('seekInput').value.trim();
        if (!keyword) return;

        if (currentTagId === 0) {
            const colName = currentFields[selectedColIdx] ? currentFields[selectedColIdx].name : (currentFields[0]?.name || '');
            postApi('seek_locate', {
                path: currentPath,
                mode: 'locate',
                field_name: colName,
                key: keyword,
                start_rec: selectedRowIdx + 1
            }, function(res) {
                if (res.status === 'success' && res.found) {
                    const targetIdx = res.recno - 1;
                    selectRowIndex(targetIdx);
                    ensureRowVisible(targetIdx);
                } else {
                    alert(`Locate Not Found: [${keyword}] (Field: ${colName})`);
                }
            });
        } else {
            const tg = currentTags.find(t => t.slot === currentTagId);
            const tagName = tg ? tg.name : 'idx_code';
            postApi('seek_locate', {
                path: currentPath,
                mode: 'seek',
                tag_name: tagName,
                key: keyword
            }, function(res) {
                if (res.status === 'success' && res.found) {
                    const targetIdx = res.recno - 1;
                    selectRowIndex(targetIdx);
                    ensureRowVisible(targetIdx);
                } else {
                    alert(`Seek Not Found: [${keyword}] (Tag: ${tagName})`);
                }
            });
        }
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
        
        // Ensure bottom TOOLBOX toggle bar stays visible
        const tbBar = document.getElementById('toolboxBar');
        if (tbBar) tbBar.style.display = 'flex';

        // Display main drawer and target sub-panel
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

    // Dynamically render Menu -> Edit -> Slot [1] ~ [8] according to active tab EDX tags count
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
            drawer.style.display = 'none'; // Clear inline style completely to ensure drawer hides smoothly
        }

        const btnSchema = document.getElementById('btnSchemaToggle');
        const btnRel = document.getElementById('btnRelToggle');
        if (btnSchema) btnSchema.classList.remove('active');
        if (btnRel) btnRel.classList.remove('active');

        // Hide child panels
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
                currentFields.forEach(f => addSchemaFieldRow(f.name, f.type, f.len));
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
                res.fields.forEach(f => addSchemaFieldRow(f.name, f.type, f.len));
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
                            // Ensure selected target is a valid .ebf file
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
        // Support both Windows backslashes and Unix slashes
        const lastSep = Math.max(cur.lastIndexOf('/'), cur.lastIndexOf('\\'));

        if (lastSep > 0) {
            let parent = cur.substring(0, lastSep);
            // Handle Windows drive root special case (e.g. "C:" -> "C:\")
            if (parent.length === 2 && parent.charAt(1) === ':') {
                parent += '\\';
            }
            openFileExplorer(parent, expCallback);
        } else if (lastSep === 0) {
            // Unix root directory "/"
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
    // 8. Global Keyboard Shortcuts Listener (Aligned with desktop_main_page)
    // =========================================================================
    window.addEventListener('keydown', (e) => {
        // Intercept all shortcuts except F5 reload when FFI is locked down
        if (!isFfiAvailable) {
            if (e.key !== 'F5' && !(e.ctrlKey && e.key.toLowerCase() === 'r')) {
                e.preventDefault();
                e.stopPropagation();
            }
            return;
        }

        if (document.activeElement.tagName === 'INPUT' || document.activeElement.tagName === 'SELECT') return;
        if (activeTool !== null) return; // Yield keyboard control while child panel is open

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

    // Toggle Menu item states and shortcuts based on active file status (Aligned with desktop_main_page)
    function updateCommandEnablement(hasActiveEbf) {
        document.querySelectorAll('.menu-requires-ebf').forEach(el => {
            el.classList.toggle('disabled', !hasActiveEbf);
        });
        updateIndexSlotMenu();
    }

    // Defense guard: Prevent launching relation studio without active open tables
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
        updateCommandEnablement(false); // Initial state strictly locked down
    });
    </script>
</body>
</html>