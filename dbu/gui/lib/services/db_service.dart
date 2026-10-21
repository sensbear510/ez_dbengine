// ignore_for_file: non_constant_identifier_names

/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * This source code may not be redistributed without the copyright owner's
 * written consent.
 *
 * @ Author : CHI-HSIUNG YANG
 * @ File   : db_service.dart
 */

library services;

import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'ez_dbengine.dart';
import '../toolbox/ez_output.dart';

/// Centralized Database Engine Master Service
/// 100% encapsulates all Group A ~ G APIs exposed by EzDB with strict u64 Handle Defense Guards.
class DbService {
  // Singleton Pattern
  static final DbService _instance = DbService._internal();
  DbService._internal();

  static DbService get instance => _instance;

  // Member Variables strictly adhering to m_ + type + name convention
  late final EzDB m_ezDb = EzDB();
  int m_iWorkAreaHandle = 0;
  String m_strCurrentFilePath = '';
  String m_strCurrentFileName = '';
  bool m_bIsFileOpen = false;

  // Getters for status checking
  int get m_iHandle => m_iWorkAreaHandle;
  bool get m_bIsOpen => m_bIsFileOpen;
  String get m_strFileName => m_strCurrentFileName;
  String get m_strFilePath => m_strCurrentFilePath;

  // =========================================================================
  // 🛡️ INTERNAL DEFENSE & HANDLE RESOLUTION GUARD
  // =========================================================================

  /// Clears active WorkArea EDX tag slots before schema/tag reconstruction
  void clearTags({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'clearTags');
    if (h == 0) return;

    ezOutput('[INFO] Clearing inline EDX tag slots on handle #0x${_toHex(h)}...');
    m_ezDb.clearTags(h);
  }

  /// Safely cleans up unused EDX physical files with reference guarding against duplicate tags
  void safeCleanupUnusedEdxFiles({
    required String strDbName,
    required List<String> lstOldTagNames,
    required List<String> lstNewTagNames,
  }) {
    final Set<String> setRemainingTagNames =
        lstNewTagNames.map((String strName) => strName.trim().toLowerCase()).where((String strName) => strName.isNotEmpty).toSet();

    for (final String strOldName in lstOldTagNames) {
      final String strCleanOldName = strOldName.trim();
      if (strCleanOldName.isEmpty) continue;

      final String strLowerOldName = strCleanOldName.toLowerCase();

      // Security Gatekeeper:
      // Delete physical file ONLY if the tag name no longer exists in the updated Header list.
      if (!setRemainingTagNames.contains(strLowerOldName)) {
        final String strEdxPath = '${strDbName}_$strCleanOldName.edx';
        final File fileEdx = File(strEdxPath);

        if (fileEdx.existsSync()) {
          try {
            fileEdx.deleteSync();
            ezOutput('[EBF Safe Cleanup] Removed obsolete index file: $strEdxPath');
          } catch (e) {
            ezOutput('[EBF Safe Cleanup] Failed to delete index file ($strEdxPath): $e');
          }
        }
      } else {
        ezOutput('[EBF Safe Cleanup] Skipped deleting [$strCleanOldName.edx] - tag still referenced in Header.');
      }
    }
  }

  /// Resolves target handle and executes strict NULL guard check (h == 0).
  /// Avoids signed logic comparison errors (h <= 0) on 64-bit unsigned pointer addresses.
  int _resolveHandle(int? iHandle, String strMethodName) {
    final int h = iHandle ?? m_iWorkAreaHandle;
    if (h == 0) {
      ezOutput('[ERROR db_service] $strMethodName failed: WorkArea Handle is NULL (#0x0). Operation aborted.');
      return 0;
    }
    return h;
  }

  /// Converts Dart signed 64-bit int handle into unsigned 64-bit upper Hex string
  String _toHex(int iHandle) {
    return iHandle.toUnsigned(64).toRadixString(16).toUpperCase();
  }

  // =========================================================================
  // 🚀 GROUP A: Initialization, Creation, and Storage Management
  // =========================================================================

  /// Initializes the underlying EZ_ENGINE I/O core
  int ioInit({int mode = -1, int slotCount = 0, int blockSize = 0}) {
    ezOutput('[INFO] Executing ioInit(mode: $mode, slots: $slotCount, blockSize: $blockSize)...');
    return m_ezDb.ioInit(mode: mode, slotCount: slotCount, blockSize: blockSize);
  }

  /// Builds database file and default index from field schema list
  int create(String strPath, List<EzField> lstFields) {
    ezOutput('[INFO] Creating database => $strPath with ${lstFields.length} fields.');
    return m_ezDb.create(strPath, lstFields);
  }

  /// Creates an index tag on specified database WorkArea
  int createIndex(String strTagName, String strFieldsStr, {bool bIsUnique = false, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'createIndex');
    if (h == 0) return -1;

    final String strCleanTag = strTagName.trim();
    if (strCleanTag.isEmpty) return -1;

    ezOutput('[INFO] Creating index tag [$strCleanTag] on handle #0x${_toHex(h)}...');

    return m_ezDb.createIndex(h, strCleanTag, strFieldsStr, isUnique: bIsUnique);
  }

  /// Schema Evolution: Alters table structure and migrates data
  int alter(String strPath, List<EzField> lstFields, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'alter');
    if (h == 0) return -1;

    ezOutput('[INFO] Altering schema on handle #0x${_toHex(h)} => $strPath');
    return using((arena) {
      final mapPtr = lstFields.toNativeMap(arena);
      return m_ezDb.alter(h, strPath, mapPtr, nullptr);
    });
  }

  /// Recovery: Reconstructs database headers and indexes from existing files
  int reconstruct(String strPath, Pointer<EzMigrateReport> ptrReport, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'reconstruct');
    if (h == 0) return -1;

    ezOutput('[INFO] Reconstructing database on handle #0x${_toHex(h)} => $strPath');
    return m_ezDb.reconstruct(h, strPath, ptrReport);
  }

  /// Opens database dataset and registers current WorkArea handle
  int use(String strPath, Pointer<EzMigrateReport> ptrReport) {
    ezOutput('[INFO] Opening database via use() => $strPath');
    int iHandle = m_ezDb.use(strPath, ptrReport);

    // u64 Valid Check: Non-zero represents valid WorkArea pointer address
    if (iHandle != 0) {
      m_iWorkAreaHandle = iHandle;
      m_strCurrentFilePath = strPath;
      m_strCurrentFileName = strPath.split(RegExp(r'[/\\]')).last;
      m_bIsFileOpen = true;

      ezOutput('[INFO] Database opened successfully! Handle = #0x${iHandle.toUnsigned(64).toRadixString(16)}');
    } else {
      ezOutput('[ERROR] Failed to open database, NULL u64 handle returned from C engine.');
      m_bIsFileOpen = false;
    }
    return iHandle;
  }

  /// Closes database handle
  int close({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'close');
    if (h == 0) return -1;

    ezOutput('[INFO] Closing database handle #0x${_toHex(h)}');
    int iRes = m_ezDb.close(h);

    if (h == m_iWorkAreaHandle) {
      m_iWorkAreaHandle = 0;
      m_bIsFileOpen = false;
      m_strCurrentFileName = '';
      m_strCurrentFilePath = '';
    }
    return iRes;
  }

  /// Closes all active database handles
  int closeAll() {
    ezOutput('[INFO] Closing all active database handles...');
    m_iWorkAreaHandle = 0;
    m_bIsFileOpen = false;
    m_strCurrentFileName = '';
    m_strCurrentFilePath = '';
    return m_ezDb.closeAll();
  }

  /// Sets auto-vacuum threshold parameters
  void setVacuum(double dbThreshold, int iMinDeleted, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'setVacuum');
    if (h == 0) return;

    m_ezDb.setVacuum(h, dbThreshold, iMinDeleted);
  }

  /// Complete pipeline for updating EBF schema, rebuilding EDX indexes, and cleaning obsolete index files
  int saveEbfSchema({
    required String strDbPath,
    required String strDbName,
    required List<EzField> lstFields,
    required List<EzTag> lstNewTags,
    required bool bSchemaChanged,
    required bool bIndexChanged,
    int? iHandle,
  }) {
    int hTable = iHandle ?? 0;
    bool bNeedCloseHandle = false;

    // Step 1: Attempt resolving active handle from DbService state if not explicitly provided
    if (hTable == 0 && m_bIsOpen) {
      final String strNormalizedInput = File(strDbPath).absolute.path.toLowerCase();
      final String strNormalizedActive = File(m_strFilePath).absolute.path.toLowerCase();
      if (strNormalizedInput == strNormalizedActive) {
        hTable = m_iHandle;
      }
    }

    // Step 2: Fallback to opening independent handle via use() ONLY if no active handle exists
    if (hTable == 0) {
      hTable = use(strDbPath, nullptr);
      bNeedCloseHandle = true;
    }

    if (hTable == 0) {
      ezOutput('[ERROR db_service] Failed to acquire WorkArea handle for path: $strDbPath');
      return -1;
    }

    try {
      // Snapshot existing tag names before applying changes
      final List<EzTag> lstOldTags = getTags(iHandle: hTable);
      final List<String> lstOldTagNames = lstOldTags.map((EzTag t) => t.name).toList();

      // Execute physical schema alter if FDT fields were modified
      if (bSchemaChanged) {
        final int iAlterStatus = alter(strDbPath, lstFields, iHandle: hTable);
        if (iAlterStatus != 0) {
          ezOutput('[ERROR db_service] Engine alter failed with status code: $iAlterStatus');
          return iAlterStatus;
        }
      }

      // Rebuild / create EDX index tags if schema or tags changed
      if (bIndexChanged || bSchemaChanged) {
        // 🎯 CRITICAL FIX: Clear old inline tag slots before writing updated tag definitions!
        clearTags(iHandle: hTable);

        for (final EzTag tag in lstNewTags) {
          createIndex(
            tag.name,
            tag.expression,
            bIsUnique: tag.isUnique,
            iHandle: hTable,
          );
        }
      }

      // Safely clean up obsolete EDX physical files with reference guarding
      final List<String> lstNewTagNames = lstNewTags.map((EzTag t) => t.name).toList();
      safeCleanupUnusedEdxFiles(
        strDbName: strDbName,
        lstOldTagNames: lstOldTagNames,
        lstNewTagNames: lstNewTagNames,
      );

      return 0;
    } catch (e) {
      ezOutput('[EXCEPTION db_service] Error during saveEbfSchema: $e');
      return -1;
    } finally {
      // Release temporary handle only if it was opened internally
      if (bNeedCloseHandle && hTable != 0) {
        close(iHandle: hTable);
      }
    }
  }

  // =========================================================================
  // 🚀 GROUP B: Navigation and State
  // =========================================================================

  int goTop({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'goTop');
    return h == 0 ? -1 : m_ezDb.goTop(h, tagId: tagId, tagName: tagName);
  }

  int goBottom({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'goBottom');
    return h == 0 ? -1 : m_ezDb.goBottom(h, tagId: tagId, tagName: tagName);
  }

  int skip(int iCount, {int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'skip');
    return h == 0 ? -1 : m_ezDb.skip(h, iCount, tagId: tagId, tagName: tagName);
  }

  int goTo(int iRecNo, {int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'goTo');
    return h == 0 ? -1 : m_ezDb.goTo(h, iRecNo, tagId: tagId, tagName: tagName);
  }

  bool isEof({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'isEof');
    return h == 0 ? true : m_ezDb.isEof(h, tagId: tagId, tagName: tagName);
  }

  bool isBof({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'isBof');
    return h == 0 ? true : m_ezDb.isBof(h, tagId: tagId, tagName: tagName);
  }

  bool isFound({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'isFound');
    return h == 0 ? false : m_ezDb.isFound(h, tagId: tagId, tagName: tagName);
  }

  int getRecNo({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'getRecNo');
    return h == 0 ? 0 : m_ezDb.getRecNo(h, tagId: tagId, tagName: tagName);
  }

  int getLastRec({int? iHandle, int tagId = 0, String tagName = ''}) {
    final int h = _resolveHandle(iHandle, 'getLastRec');
    return h == 0 ? 0 : m_ezDb.getLastRec(h, tagId: tagId, tagName: tagName);
  }

  int getRecSiz({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getRecSiz');
    return h == 0 ? 0 : m_ezDb.getRecordSize(h);
  }

  int getRecordSize({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getRecordSize');
    return h == 0 ? 0 : m_ezDb.getRecordSize(h);
  }

  int getRecordCount({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getRecordCount');
    return h == 0 ? 0 : m_ezDb.getRecordCount(h);
  }

  int getCurrentRec({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getCurrentRec');
    return h == 0 ? 0 : m_ezDb.getRecNo(h);
  }

  int getDeleteCount({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getDeleteCount');
    return h == 0 ? 0 : m_ezDb.getDeleteCount(h);
  }

  // =========================================================================
  // 🚀 GROUP C: Data Manipulation and Search
  // =========================================================================

  /// Single-string key seek wrapper
  bool seekByTag(String strTagName, String strKey, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'seekByTag');
    if (h == 0) return false;
    return m_ezDb.seekByTag(h, strTagName, strKey);
  }

  /// Synchronous array-based seek by Index Tag Name
  /// Smart Seek entry point: Automatically selects single-field or array API based on the tag's true fieldCount
  bool seekByName(String strTagName, List<String> lstKeys, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'seekByName');
    if (h == 0) return false;
    if (lstKeys.isEmpty) return false;

    // 1. Retrieve all tag information for the current WorkArea and locate the target tag's actual fieldCount
    final List<EzTag> lstTags = getTags(iHandle: h);
    EzTag? targetTag;
    for (final tag in lstTags) {
      if (tag.name.toLowerCase() == strTagName.toLowerCase()) {
        targetTag = tag;
        break;
      }
    }

    // Return false immediately if the tag name cannot be found
    if (targetTag == null) return false;

    // 2. Strict validation: The number of provided keys must strictly match the tag's defined fieldCount
    if (lstKeys.length != targetTag.fieldCount) {
      ezOutput(
          '[ERROR db_service] Seek failed: Tag [$strTagName] requires ${targetTag.fieldCount} key(s), but ${lstKeys.length} was provided.');
      return false;
    }

    // 3. Automatically switch to the most efficient and accurate underlying API based on the true fieldCount
    if (targetTag.fieldCount == 1) {
      // Single-field index: Route directly to the optimized ez_dbseek_by_tag
      ezOutput('[MESSAGE] call m_ezDB.seekByTag with [$strTagName] and [${lstKeys.first}]');
      return m_ezDb.seekByTag(h, strTagName, lstKeys.first);
    } else {
      // Composite-field index: Route to ez_dbseek_by_tag_array for array query
      ezOutput('[MESSAGE] call m_ezDB.seekByName with  [$strTagName] ');
      return m_ezDb.seekByName(h, strTagName, lstKeys);
    }
  }

  /// Synchronous array-based seek by Index Tag ID
  bool seekById(int iTagId, List<String> lstKeys, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'seekById');
    if (h == 0) return false;
    return m_ezDb.seekById(h, iTagId, lstKeys);
  }

  /// Locates field value in unindexed or indexed dataset
  int locate(String strFieldName, String strTargetValue, {bool bPartialMatch = false, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'locate');
    if (h == 0) return -1;
    return m_ezDb.locate(h, strFieldName, strTargetValue, partialMatch: bPartialMatch);
  }

  /// Appends delimited text record
  int append(String strData, {int iRecCount = 1, String strDelimiter = '|', int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'append');
    if (h == 0) return -1;
    return m_ezDb.append(h, strData, recCount: iRecCount, delimiter: strDelimiter);
  }

  /// Replaces current row with delimited text record (ez_db_row_replace)
  int rowReplace(String strData, {String strDelimiter = ',', int? rowId, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'rowReplace');
    if (h == 0) return -1;
    final int targetRow = rowId ?? getRecNo(iHandle: h);
    return m_ezDb.rowReplace(h, targetRow, strData, delimiter: strDelimiter);
  }

  /// Inserts delimited text record at current position
  int insert(String strData, {int iRecCount = 1, String strDelimiter = '|', int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'insert');
    if (h == 0) return -1;
    return m_ezDb.insert(h, strData, recCount: iRecCount, delimiter: strDelimiter);
  }

  /// Field-level update: Updates a specific field by name
  int replace(String strFieldName, String strValue, {int? rowId, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'replace');
    if (h == 0) return -1;
    final int targetRow = rowId ?? getRecNo(iHandle: h);
    return m_ezDb.replace(h, targetRow, strFieldName, strValue);
  }

  /// Low-level record fetch into native buffer
  int getRecord(
    Pointer<Void> ptrBuffer,
    int iBufferSize, {
    bool bIncludeDeleted = false,
    int tagId = 0,
    String tagName = '',
    int? iHandle,
  }) {
    final int h = _resolveHandle(iHandle, 'getRecord');
    if (h == 0) return -1;
    return m_ezDb.getRecord(h, ptrBuffer, iBufferSize, includeDeleted: bIncludeDeleted, tagId: tagId, tagName: tagName);
  }

  /// Reads physical record and maps directly to a custom Dart Model Class
  T? readModel<T>(
    T Function(EzRecordReader reader) fnMapper, {
    bool bIncludeDeleted = false,
    int tagId = 0,
    String tagName = '',
    int? iHandle,
  }) {
    final int h = _resolveHandle(iHandle, 'readModel');
    if (h == 0) return null;
    return m_ezDb.readModel<T>(h, fnMapper, includeDeleted: bIncludeDeleted, tagId: tagId, tagName: tagName);
  }

  /// Reads current physical record directly as a pure Dart EzRecordReader
  EzRecordReader? readRecord({
    bool includeDeleted = false,
    int tagId = 0,
    String tagName = '',
    int? iHandle,
  }) {
    final int h = _resolveHandle(iHandle, 'readRecord');
    if (h == 0) return null;
    return m_ezDb.readRecord(h, includeDeleted: includeDeleted, tagId: tagId, tagName: tagName);
  }

  /// Reads batch physical records directly as EzRecordReader list with strict physical stride inspection
  List<EzRecordReader> readRecordVector({
    int iCount = 200,
    int tagId = 0,
    String tagName = '',
    bool bStripStr = true,
    bool bIncludeDeleted = true,
    int? iHandle,
  }) {
    final int h = _resolveHandle(iHandle, 'readRecordVector');
    if (h == 0) return <EzRecordReader>[];

    final List<EzRecordReader> lstReaders = m_ezDb.readRecordVector(
      h,
      count: iCount,
      tagId: tagId,
      tagName: tagName,
      stripStr: bStripStr,
      includeDeleted: bIncludeDeleted,
    );

    return lstReaders;
  }

  /// Checks if current record is marked as deleted
  bool isDeleted([int? iRecNo, int? iHandle]) {
    final int h = _resolveHandle(iHandle, 'isDeleted');
    if (h == 0) return false;

    final int targetRow = iRecNo ?? getRecNo(iHandle: h);
    return m_ezDb.isDeleted(h, targetRow);
  }

  /// Soft deletes current record (ez_db_delete)
  int deleteRecord({int? rowId, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'deleteRecord');
    if (h == 0) return -1;
    final int targetRow = rowId ?? getRecNo(iHandle: h);
    return m_ezDb.deleteRecord(h, targetRow);
  }

  int recallRecord({int? rowId, int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'recallRecord');
    if (h == 0) return -1;
    final int targetRow = rowId ?? getRecNo(iHandle: h);
    return m_ezDb.recallRecord(h, targetRow);
  }

  /// Purges soft-deleted records from database file (ez_db_pack)
  int pack(String strPath, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'pack');
    if (h == 0) return -1;

    ezOutput('[INFO] Packing database handle #0x${_toHex(h)} => $strPath');
    return m_ezDb.pack(h, strPath);
  }

  /// Commits pending database transaction
  int commit({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'commit');
    return h == 0 ? -1 : m_ezDb.commit(h);
  }

  // =========================================================================
  // 🚀 GROUP D: Utility and Security Defense
  // =========================================================================

  double getProgress() => m_ezDb.getProgress();

  int verifySchema(Pointer<Void> ptrWa, int iExpectedHash) {
    return m_ezDb.verifySchema(ptrWa, iExpectedHash);
  }

  List<String> getFieldNames([int? iHandle, String strDelimiter = ',']) {
    final int h = _resolveHandle(iHandle, 'getFieldNames');
    if (h == 0) return <String>[];
    return m_ezDb.getFieldNames(h, strDelimiter);
  }

  // =========================================================================
  // 🚀 GROUP E: Event Observation and State Monitoring
  // =========================================================================

  void setStateObserver(Pointer<NativeFunction<EzStateObserverNative>> ptrCb) {
    m_ezDb.setStateObserver(ptrCb);
  }

  void dumpWorkarea({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'dumpWorkarea');
    if (h == 0) return;
    m_ezDb.dumpWorkarea(h);
  }

  int purgeDuplicates(int iTagId, int iKeepRowId, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'purgeDuplicates');
    if (h == 0) return -1;
    return m_ezDb.purgeDuplicates(h, iTagId, iKeepRowId);
  }

  int extractDuplicates(int iTagId, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'extractDuplicates');
    if (h == 0) return -1;
    return m_ezDb.extractDuplicates(h, iTagId);
  }

  void dumpRecord(Pointer<Void> ptrRecordPayload, {int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'dumpRecord');
    if (h == 0) return;
    m_ezDb.dumpRecord(h, ptrRecordPayload);
  }

  // =========================================================================
  // 🚀 GROUP F: Indexing and Vectorized Access
  // =========================================================================

  /// Dynamically retrieves the index expression (e.g. "code" or "date+code") for the specified tag
  String getIndexKey({int tagId = 0, String tagName = '', int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getIndexKey');
    if (h == 0) return '';
    return m_ezDb.getIndexKey(h, tagId: tagId, tagName: tagName);
  }

  /// Vectorized record fetching wrapping C ez_db_get_record_vector
  int getRecordVector(
    Pointer<Void> ptrOutStructArray,
    Pointer<Uint32> ptrPCount,
    int iStructSize, {
    int tagId = 0,
    String tagName = '',
    bool bStripStr = true,
    bool include_deleted = true,
    int? iHandle,
  }) {
    final int h = _resolveHandle(iHandle, 'getRecordVector');
    if (h == 0) return -1;

    return m_ezDb.getRecordVector(
      h,
      ptrOutStructArray,
      ptrPCount,
      iStructSize,
      tagId: tagId,
      tagName: tagName,
      stripStr: bStripStr,
      include_deleted: include_deleted,
    );
  }

  /// Retrieves active WorkArea FDT field schema list directly as List<EzField>
  List<EzField> getFdt({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getFdt');
    if (h == 0) return <EzField>[];

    final List<EzField> lstFields = m_ezDb.getFdt(h);
    if (lstFields.isEmpty) {
      ezOutput('[WARNING db_service] getFdt (Handle #0x${_toHex(h)}): ez_dbEngine returned empty field list.');
    }
    return lstFields;
  }

  /// Retrieves active WorkArea EDX index tags directly as List<EzTag>
  List<EzTag> getTags({int? iHandle}) {
    final int h = _resolveHandle(iHandle, 'getTags');
    if (h == 0) return <EzTag>[];

    final List<EzTag> lstTags = m_ezDb.getTags(h);
    return lstTags;
  }

  // =========================================================================
  // 🚀 GROUP G: Relation View Subsystem & Multi-Table Query Management
  // =========================================================================

  /// Initializes the global Relation Manager subsystem
  int rlMgrInit() {
    ezOutput('[INFO] Initializing Relation Manager Subsystem...');
    return m_ezDb.rlMgrInit();
  }

  /// Cleans up the global Relation Manager subsystem
  int rlMgrCleanup() {
    ezOutput('[INFO] Cleaning up Relation Manager Subsystem...');
    return m_ezDb.rlMgrCleanup();
  }

  /// One-Shot Declarative Builder: Audits geometry & spawns Relation View Handle
  int rlBuildView(RlViewDesc desc) {
    ezOutput('[INFO] Building Relation View [${desc.relationName}] with ${desc.ebfHandles.length} tables...');
    int hRel = m_ezDb.rlBuildView(desc);
    if (hRel != 0) {
      ezOutput('[INFO] Relation View [${desc.relationName}] created! Handle = #0x${_toHex(hRel)}');
    } else {
      ezOutput('[ERROR] Failed to build Relation View [${desc.relationName}], Key geometry or schema mismatch!');
    }
    return hRel;
  }

  /// Destroys and unregisters a Relation View
  int rlDestroyView(int hRel) {
    if (hRel == 0) {
      ezOutput('[ERROR db_service] rlDestroyView failed: Relation Handle is NULL (#0x0)');
      return -1;
    }
    ezOutput('[INFO] Destroying Relation View Handle #0x${_toHex(hRel)}...');
    return m_ezDb.rlDestroyView(hRel);
  }

  /// Retrieves stitched payload record vector directly from Relation View
  List<EzRecordReader> rlGetRecordVector(int hRel, int recordSize, {int count = 200}) {
    if (hRel == 0) {
      ezOutput('[ERROR db_service] rlGetRecordVector failed: Invalid relation handle #0x0');
      return <EzRecordReader>[];
    }
    return m_ezDb.rlGetRecordVector(hRel, recordSize, count: count);
  }

  /// Exports a relation view definition descriptor to an .ERL file
  int rlSaveViewFile(RlViewDesc desc, String strErlPath) {
    ezOutput('[INFO] Exporting Relation View definition to $strErlPath...');
    return m_ezDb.rlSaveViewFile(desc, strErlPath);
  }

  /// Imports an .ERL file and spawns active relation handle directly
  int rlLoadViewFile(String strErlPath, List<int> lstEbfHandles) {
    ezOutput('[INFO] Importing .ERL view file from $strErlPath...');
    int hRel = m_ezDb.rlLoadViewFile(strErlPath, lstEbfHandles);
    if (hRel != 0) {
      ezOutput('[INFO] Imported .ERL View successfully! Handle = #0x${_toHex(hRel)}');
    } else {
      ezOutput('[ERROR] Failed to import .ERL file. File corrupt or geometry mismatch!');
    }
    return hRel;
  }
}
