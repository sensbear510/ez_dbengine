/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * @ File   : pad_main_page.dart
 */

import 'dart:ffi' show nullptr; // 🎯 僅引入 nullptr，徹底根除與 Material Size 的衝突
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/db_service.dart';
import '../../services/ez_dbengine.dart';
import '../../theme/app_theme.dart';
import '../../toolbox/ez_notification.dart';
import '../../toolbox/ez_output.dart';
import '../../toolbox/language.dart';
import '../../toolbox/toolbox.dart';
import '../../toolbox/ebf_tab_context.dart';
import '../desktop/desktop_main_page.dart';
import '../../toolbox/widgets/about_dialog_panel.dart';

class PadMainPage extends StatefulWidget {
  static const String routeName = '/pad_main';
  final String? strInitialFilePath;

  const PadMainPage({
    super.key,
    this.strInitialFilePath,
  });

  @override
  State<PadMainPage> createState() => _PadMainPageState();
}

class _PadMainPageState extends State<PadMainPage> {
  final ScrollController m_scrollControllerVerticalFrozen = ScrollController();

  String m_strCurrentSearchMode = 'Locate';
  int m_iCurrentRecNo = 0;
  int m_iTotalRecs = 0;
  int m_iDeletedCount = 0;
  bool m_bIsDirty = false;
  bool m_bIsBof = false;
  bool m_bIsEof = false;

  final DbService m_dbService = DbService.instance;
  final ToolBox m_toolBox = ToolBox.instance;
  final Language m_language = Language.instance;

  String m_strActiveEbfPath = '';
  final List<EbfTabContext> m_listTabs = <EbfTabContext>[];
  String? m_strActiveTabId;

  int m_iActiveSlotIndex = 0;
  int m_iSelectedRowIndex = 0;
  int m_iSelectedColIndex = 0;
  int? m_iEditingRowIndex;

  final TextEditingController m_controllerSeekInput = TextEditingController();
  final FocusNode m_focusNodeSeekInput = FocusNode();
  final ScrollController m_scrollControllerHorizontalHeader = ScrollController();
  final ScrollController m_scrollControllerHorizontalBody = ScrollController();
  final ScrollController m_scrollControllerVertical = ScrollController();

  final Map<String, TextEditingController> m_mapCellControllers = {};

  // 高效能分塊緩衝系統
  static const int kChunkSize = 200;
  static const int kMaxCacheChunks = 10;
  final Map<int, Map<String, dynamic>> m_mapRowCache = <int, Map<String, dynamic>>{};
  final Set<int> m_setLoadingChunks = <int>{};
  final ValueNotifier<int> m_notifierBufferUpdate = ValueNotifier<int>(0);

  EbfTabContext? get m_activeTab {
    if (m_strActiveTabId == null || m_listTabs.isEmpty) return null;
    return m_listTabs.firstWhere(
      (EbfTabContext tab) => tab.strId == m_strActiveTabId,
      orElse: () => m_listTabs.first,
    );
  }

  /// 是否處於 EDX Tag 索引導航模式
  bool get m_bIsTagActive => m_strCurrentSearchMode.startsWith('Seek');

  /// 取得當前作用中的 tag_id (1 ~ 8)；若為 Locate/Natural 模式則傳 0
  int get m_iCurrentTagId {
    if (!m_bIsTagActive) return 0;
    final int iSlot = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
    return (iSlot >= 0 && iSlot < 8) ? (iSlot + 1) : 0;
  }

  int get m_iActiveTabIndex {
    if (m_strActiveTabId == null) return -1;
    return m_listTabs.indexWhere((tab) => tab.strId == m_strActiveTabId);
  }

  @override
  void initState() {
    super.initState();
    if (widget.strInitialFilePath != null && widget.strInitialFilePath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEbfFile(widget.strInitialFilePath!);
      });
    }
    ezOutput('[INFO] PadMainPage Workstation Initialized with Touch Craftsman Engine.');
  }

  @override
  void dispose() {
    for (final EbfTabContext tab in m_listTabs) {
      if (tab.iHandle != 0) {
        try {
          m_dbService.close(iHandle: tab.iHandle);
        } catch (e) {
          ezOutput('[ERROR] Failed releasing handle ${tab.iHandle}: $e');
        }
      }
    }
    m_scrollControllerVerticalFrozen.dispose();
    m_controllerSeekInput.dispose();
    m_focusNodeSeekInput.dispose();
    m_scrollControllerHorizontalHeader.dispose();
    m_scrollControllerHorizontalBody.dispose();
    m_scrollControllerVertical.dispose();
    _clearCellControllers();
    super.dispose();
  }

  void _clearCellControllers() {
    for (final controller in m_mapCellControllers.values) {
      controller.dispose();
    }
    m_mapCellControllers.clear();
  }

  void _clearDataBuffer() {
    m_mapRowCache.clear();
    m_setLoadingChunks.clear();
    m_notifierBufferUpdate.value++;
  }

  Future<void> _handleOpenEbfDialog() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['ebf'],
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        await _openEbfFile(result.files.single.path!);
      }
    } catch (e) {
      ezOutput('[ERROR] FilePicker failed: $e');
    }
  }

  void _handleOpenNewSchema() {
    final int iExistingDraftIndex = m_listTabs.indexWhere(
      (EbfTabContext tab) => tab.iHandle == 0 && tab.strFilePath.isEmpty && tab.strFileName == 'Untitled.ebf',
    );

    if (iExistingDraftIndex != -1) {
      final EbfTabContext existingDraft = m_listTabs[iExistingDraftIndex];
      setState(() {
        m_strActiveTabId = existingDraft.strId;
        m_strActiveEbfPath = '';
        existingDraft.strActiveBottomTool = 'schema';
        _clearDataBuffer();
        _clearCellControllers();
        m_iSelectedRowIndex = 0;
        _updateStatusBarMetrics();
      });
      return;
    }

    setState(() {
      final String strDraftId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final newTab = EbfTabContext(
        strId: strDraftId,
        strFileName: 'Untitled.ebf',
        strFilePath: '',
        iHandle: 0,
        strActiveBottomTool: 'schema',
      );
      m_listTabs.add(newTab);
      m_strActiveTabId = strDraftId;
      _clearDataBuffer();
      _clearCellControllers();
      m_iSelectedRowIndex = 0;
      _updateStatusBarMetrics();
    });
  }

  void _convertDraftToOpenedEbf(String strDraftTabId, String strFilePath) {
    final File file = File(strFilePath);
    final String strNormalizedPath = file.absolute.path;
    Directory.current = file.parent.path;

    final int iIndex = m_listTabs.indexWhere((t) => t.strId == strDraftTabId);
    final int iHandle = m_dbService.use(strNormalizedPath, nullptr);
    if (iHandle == 0) return;

    final String strFileName = strNormalizedPath.split(RegExp(r'[/\\]')).last;
    final List<EzTag> lstTags = m_dbService.getTags(iHandle: iHandle);
    final List<String> lstEdxKeys = lstTags.map((EzTag t) => '${t.name} (${t.expression})').toList();

    final newTab = EbfTabContext(
      strId: 'tab_${iHandle}_${DateTime.now().millisecondsSinceEpoch}',
      strFileName: strFileName,
      strFilePath: strNormalizedPath,
      iHandle: iHandle,
      listEdxKeys: lstEdxKeys,
      strActiveBottomTool: null,
    );

    setState(() {
      if (iIndex != -1) {
        m_listTabs[iIndex] = newTab;
      } else {
        m_listTabs.add(newTab);
      }
      m_strActiveTabId = newTab.strId;
      m_strActiveEbfPath = strNormalizedPath;
      _clearDataBuffer();
      _clearCellControllers();
      m_iSelectedRowIndex = 0;
      _updateStatusBarMetrics();
    });
  }

  Future<bool> _openEbfFile(String strFilePath) async {
    try {
      final String strNormalizedPath = File(strFilePath).absolute.path;
      final File file = File(strFilePath);
      Directory.current = file.parent.path;

      final String strFileNameOnly = strNormalizedPath.split(RegExp(r'[/\\]')).last;
      final int iExistingIndex = m_listTabs.indexWhere(
        (EbfTabContext tab) =>
            tab.strFilePath.isNotEmpty && File(tab.strFilePath).absolute.path.toLowerCase() == strNormalizedPath.toLowerCase(),
      );

      if (iExistingIndex != -1) {
        final EbfTabContext existingTab = m_listTabs[iExistingIndex];
        setState(() {
          m_strActiveTabId = existingTab.strId;
          m_strActiveEbfPath = strNormalizedPath;
          m_iSelectedRowIndex = 0;
          _clearDataBuffer();
          _clearCellControllers();
          _updateStatusBarMetrics();
        });
        return true;
      }

      final int iHandle = m_dbService.use(strNormalizedPath, nullptr);
      if (iHandle == 0) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_TITLE_OPEN_FAIL'),
          message: m_language.getValue('NOTIF_MSG_OPEN_FAIL').replaceAll('{filename}', strFileNameOnly),
          icon: Icons.error_outline_rounded,
          accentColor: Colors.red,
        );
        return false;
      }

      final List<EzTag> lstTags = m_dbService.getTags(iHandle: iHandle);
      final List<String> lstEdxKeys = lstTags.map((EzTag t) {
        final String expr = t.expression.isNotEmpty ? t.expression : m_dbService.getIndexKey(tagName: t.name, iHandle: iHandle);
        return '${t.name} ($expr)';
      }).toList();

      setState(() {
        m_strActiveEbfPath = strNormalizedPath;
        final newTab = EbfTabContext(
          strId: 'tab_${iHandle}_${DateTime.now().millisecondsSinceEpoch}',
          strFileName: strFileNameOnly.isNotEmpty ? strFileNameOnly : 'Untitled.ebf',
          strFilePath: strNormalizedPath,
          iHandle: iHandle,
          listEdxKeys: lstEdxKeys,
        );
        m_listTabs.add(newTab);
        m_strActiveTabId = newTab.strId;
        _clearDataBuffer();
        _clearCellControllers();
        m_iSelectedRowIndex = 0;
        _updateStatusBarMetrics();
      });
      return true;
    } catch (e) {
      ezOutput('[EXCEPTION] Error opening EBF: $e');
      return false;
    }
  }

  void _closeTab(String strTabId) {
    setState(() {
      final int iIndex = m_listTabs.indexWhere((EbfTabContext tab) => tab.strId == strTabId);
      if (iIndex != -1) {
        final EbfTabContext removedTab = m_listTabs.removeAt(iIndex);
        if (removedTab.iHandle != 0) {
          m_dbService.close(iHandle: removedTab.iHandle);
        }
        if (m_listTabs.isNotEmpty) {
          m_strActiveTabId = m_listTabs[iIndex > 0 ? iIndex - 1 : 0].strId;
        } else {
          m_strActiveTabId = null;
          m_strActiveEbfPath = '';
        }
        _clearDataBuffer();
        _clearCellControllers();
        m_iSelectedRowIndex = 0;
        _updateStatusBarMetrics();
      }
    });
  }

  void _toggleBottomTool(String? strToolName) {
    if (m_activeTab == null) return;
    setState(() {
      m_activeTab!.strActiveBottomTool = (m_activeTab!.strActiveBottomTool == strToolName) ? null : strToolName;
    });
  }

  void _switchEdxSlot(int iSlotNum) {
    if (iSlotNum < 1 || iSlotNum > 8) return;
    final int iSlotIndex = iSlotNum - 1;

    setState(() {
      final int iCurrentActive = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
      final bool bIsCurrentlyActive = (iCurrentActive == iSlotIndex) && m_strCurrentSearchMode.startsWith('Seek');

      if (bIsCurrentlyActive) {
        // 點擊已選取 Tag -> 退回 Locate (Natural EBF 物理序)
        m_strCurrentSearchMode = 'Locate';
        if (m_activeTab != null) {
          m_activeTab!.iActiveSlotIndex = -1;
        }
      } else {
        // 啟動指定 EDX Tag
        if (m_activeTab != null) {
          m_activeTab!.iActiveSlotIndex = iSlotIndex;
        }
        m_iActiveSlotIndex = iSlotIndex;
        m_strCurrentSearchMode = 'Seek [$iSlotNum]';
      }

      // 🌟 關鍵：清空舊排序快取、重置行號與捲軸，觸發依新 EDX 排序重新載入 200 筆
      _clearDataBuffer();
      m_iSelectedRowIndex = 0;
      m_iCurrentRecNo = 1;
      if (m_scrollControllerVertical.hasClients) {
        m_scrollControllerVertical.jumpTo(0.0);
      }
      if (m_scrollControllerVerticalFrozen.hasClients) {
        m_scrollControllerVerticalFrozen.jumpTo(0.0);
      }
    });

    // 同步 C 引擎游標回到首筆 (gotop 帶入當前 tagId)
    if (m_activeTab != null && m_activeTab!.iHandle != 0) {
      m_dbService.goTop(
        iHandle: m_activeTab!.iHandle,
        tagId: m_iCurrentTagId,
      );
    }
    _updateStatusBarMetrics();
  }

  void _executeSeek({bool bSeekNext = true}) {
    final String strSeekKey = m_controllerSeekInput.text.trim();
    if (strSeekKey.isEmpty) return;
    final int? iHandle = m_activeTab?.iHandle;
    if (iHandle == null || iHandle == 0) return;

    if (m_strCurrentSearchMode == 'Locate') {
      final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
      if (lstFdt.isEmpty) return;
      final int iColIdx = (m_iSelectedColIndex >= 0 && m_iSelectedColIndex < lstFdt.length) ? m_iSelectedColIndex : 0;
      final String strTargetField = lstFdt[iColIdx].name;

      int iTargetSyncRec = m_iCurrentRecNo > 0 ? m_iCurrentRecNo : 1;
      if (bSeekNext && m_iCurrentRecNo > 0) iTargetSyncRec++;
      m_dbService.goTo(iTargetSyncRec, iHandle: iHandle);

      final int iLocateStatus = m_dbService.locate(strTargetField, strSeekKey, bPartialMatch: false, iHandle: iHandle);
      if (iLocateStatus == 0) {
        final int iFoundRecNo = m_dbService.getRecNo(iHandle: iHandle);
        if (iFoundRecNo > 0) _jumpToRowId(iFoundRecNo);
      }
    } else {
      final List<EzTag> lstTags = m_dbService.getTags(iHandle: iHandle);
      final int iSlotIndex = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
      if (iSlotIndex >= 0 && iSlotIndex < lstTags.length) {
        final String strTagName = lstTags[iSlotIndex].name;
        if (m_dbService.seekByName(strTagName, <String>[strSeekKey], iHandle: iHandle)) {
          final int iFoundRecNo = m_dbService.getRecNo(iHandle: iHandle, tagId: 0, tagName: strTagName);
          if (iFoundRecNo > 0) _jumpToRowId(iFoundRecNo);
        }
      }
    }
  }

  void _jumpToRowId(int iRowId) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iTotalRecords = m_dbService.getRecordCount(iHandle: m_activeTab!.iHandle);
    if (iRowId < 1 || iRowId > iTotalRecords) return;
    setState(() {
      m_iSelectedRowIndex = iRowId - 1;
      m_iCurrentRecNo = iRowId;
    });
    m_dbService.goTo(m_iCurrentRecNo, iHandle: m_activeTab!.iHandle);
    _updateStatusBarMetrics();
  }

  void _selectRowAndSyncEngine(int iRowIndex, {int? iColIndex}) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iHandle = m_activeTab!.iHandle;
    final int tagId = m_iCurrentTagId;
    final int iTargetTrackPos = iRowIndex + 1;

    // 1. 定位到當前軌道的第 N 個節點
    m_dbService.goTo(
      iTargetTrackPos,
      iHandle: iHandle,
      tagId: tagId,
    );

    // 2. 向 C 引擎取得該節點映射的真實 EBF 實體列號
    final int iRealRowId = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);

    setState(() {
      m_iSelectedRowIndex = iRowIndex;
      if (iColIndex != null) m_iSelectedColIndex = iColIndex;
      m_iCurrentRecNo = iRealRowId; // 🌟 狀態列顯示正確的實體列號
      m_iEditingRowIndex = null;
    });

    _updateStatusBarMetrics();
  }

  void _toggleDeleteSelectedRow(int iRowIndex) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iRecNo = iRowIndex + 1;
    final int iHandle = m_activeTab!.iHandle;
    m_dbService.goTo(iRecNo, iHandle: iHandle);
    if (m_dbService.isDeleted(iRecNo, iHandle)) {
      m_dbService.recallRecord(iHandle: iHandle);
    } else {
      m_dbService.deleteRecord(iHandle: iHandle);
    }
    _clearDataBuffer();
    _updateStatusBarMetrics();
    setState(() => m_bIsDirty = true);
  }

  void _commitRowChanges(int iRowIndex) {
    final EbfTabContext? activeTab = m_activeTab;
    if (activeTab == null || activeTab.iHandle == 0) return;
    final int iRecNo = iRowIndex + 1;
    final List<EzField> lstFdt = m_dbService.getFdt(iHandle: activeTab.iHandle);
    final List<String> lstUpdatedValues = <String>[];

    for (final EzField field in lstFdt) {
      final String strKey = '${iRowIndex}_${field.name}';
      final controller = m_mapCellControllers[strKey];
      if (controller != null) {
        lstUpdatedValues.add(controller.text.trim());
      } else {
        final Map<String, dynamic>? mapRow = m_mapRowCache[iRowIndex];
        final List<String> lstOld = mapRow != null ? (mapRow['values'] as List<String>) : <String>[];
        final int iIdx = lstFdt.indexOf(field);
        lstUpdatedValues.add((iIdx >= 0 && iIdx < lstOld.length) ? lstOld[iIdx].trim() : '');
      }
    }

    final String strCommaDelimitedData = lstUpdatedValues.join(',');
    m_dbService.goTo(iRecNo, iHandle: activeTab.iHandle);
    m_dbService.rowReplace(strCommaDelimitedData, strDelimiter: ',', iHandle: activeTab.iHandle);
    m_dbService.commit(iHandle: activeTab.iHandle);

    m_mapRowCache[iRowIndex] = <String, dynamic>{
      'iRecNo': iRecNo,
      'bIsZap': m_dbService.isDeleted(iRecNo, activeTab.iHandle),
      'values': lstUpdatedValues,
    };
    m_bIsDirty = false;
    m_notifierBufferUpdate.value++;
  }

  void _updateStatusBarMetrics() {
    final int? iHandle = m_activeTab?.iHandle;
    if (iHandle == null || iHandle == 0) {
      setState(() {
        m_iTotalRecs = 0;
        m_iCurrentRecNo = 0;
        m_iDeletedCount = 0;
        m_bIsBof = false;
        m_bIsEof = false;
      });
      return;
    }

    final int tagId = m_iCurrentTagId;

    setState(() {
      m_iTotalRecs = m_dbService.getLastRec(iHandle: iHandle, tagId: tagId);
      m_iCurrentRecNo = (m_iTotalRecs > 0) ? (m_iSelectedRowIndex + 1) : 0;
      m_iDeletedCount = m_dbService.getDeleteCount(iHandle: iHandle);
      m_bIsBof = m_dbService.isBof(iHandle: iHandle, tagId: tagId);
      m_bIsEof = m_dbService.isEof(iHandle: iHandle, tagId: tagId);
    });
  }

  List<VectorFieldInfo> _computeVectorLayout(List<EzField> lstFdt) {
    final List<VectorFieldInfo> listInfo = <VectorFieldInfo>[];
    int currentOffset = 0;
    for (final EzField f in lstFdt) {
      int vLen = f.len;
      if (f.type == 'N') vLen = 8;
      if (f.type == 'L') vLen = 1;
      listInfo.add(VectorFieldInfo(field: f, vectorOffset: currentOffset, vectorLen: vLen));
      currentOffset += vLen;
    }
    return listInfo;
  }

  String _extractVectorFieldValue(EzRecordReader reader, VectorFieldInfo info) {
    final EzField field = info.field;
    if (field.type == 'N') {
      final double dVal = reader.doubleAt(info.vectorOffset, 8);
      return field.dec > 0 ? dVal.toStringAsFixed(field.dec) : dVal.toInt().toString();
    } else if (field.type == 'L') {
      return reader.intAt(info.vectorOffset, 1) == 1 ? 'T' : 'F';
    } else if (field.type == 'B') {
      return '[BLOB ${field.len}B]';
    }
    return reader.stringAt(info.vectorOffset, info.vectorLen);
  }

  void _ensureRowBufferedOptimized(int iTargetRowIndex) {
    final EbfTabContext? activeTab = m_activeTab;
    if (activeTab == null || activeTab.iHandle == 0) return;

    final int iRecNo = iTargetRowIndex + 1;
    if (m_mapRowCache.containsKey(iTargetRowIndex)) return;

    Future.microtask(() {
      if (m_mapRowCache.containsKey(iTargetRowIndex)) return;

      final int iHandle = activeTab.iHandle;
      final int tagId = m_iCurrentTagId; // 擇一傳入 tagId (1~8 或 0)

      // 取得當前軌道的總記錄數 (Tag 模式為 node_count，Natural 為 total_recs)
      final int iTotalRecs = m_dbService.getLastRec(
        iHandle: iHandle,
        tagId: tagId,
      );
      if (iRecNo > iTotalRecs) return;

      final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
      if (lstFdt.isEmpty) return;

      if (m_mapRowCache.length > kChunkSize * kMaxCacheChunks) {
        m_mapRowCache.clear();
      }

      final int iStartRec = iRecNo;
      final int iCountToFetch = (iStartRec + kChunkSize - 1 > iTotalRecs) ? (iTotalRecs - iStartRec + 1) : kChunkSize;

      if (iCountToFetch <= 0) return;

      // 🌟 1. 定位游標：定位至該 Tag 幾何的第 iStartRec 個節點 (1-based)
      m_dbService.goTo(
        iStartRec,
        iHandle: iHandle,
        tagId: tagId,
      );

      // 🌟 2. 向量拉取：C 引擎內部自 EDX 讀出 RowID 並散佈讀取 EBF 組裝出有序切片
      final List<EzRecordReader> lstReaders = m_dbService.readRecordVector(
        iCount: iCountToFetch,
        iHandle: iHandle,
        tagId: tagId,
      );

      final List<VectorFieldInfo> lstLayout = _computeVectorLayout(lstFdt);

      for (int iIdx = 0; iIdx < lstReaders.length; iIdx++) {
        final int iCurrentTrackIndex = iStartRec + iIdx;
        final int iRowIdx = iCurrentTrackIndex - 1;
        final EzRecordReader reader = lstReaders[iIdx];

        // 取得該節點對應的 EBF 實體 RowID (用於刪除狀態與 replace 辨識)
        m_dbService.goTo(iCurrentTrackIndex, iHandle: iHandle, tagId: tagId);
        final int iPhysicalRowId = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);
        final bool bIsZap = m_dbService.isDeleted(iPhysicalRowId, iHandle);

        final List<String> lstValues = lstLayout.map((VectorFieldInfo info) {
          return _extractVectorFieldValue(reader, info);
        }).toList();

        m_mapRowCache[iRowIdx] = <String, dynamic>{
          'iRecNo': iPhysicalRowId, // 真正 EBF 實體列號
          'iTrackPos': iCurrentTrackIndex, // 當前 Key 排序下的序號 (1, 2, 3...)
          'bIsZap': bIsZap,
          'values': lstValues,
        };
      }

      m_notifierBufferUpdate.value++;
    });
  }

  Widget _buildCellDisplayOrInput({
    required int iRowIndex,
    required String strFieldName,
    required String strCellValue,
    required bool bIsSelected,
    required bool bIsCellFocused,
    required bool bIsEditing,
    required bool bIsZap,
    required ThemeData theme,
  }) {
    if (!bIsEditing) {
      return Container(
        width: 160.0,
        height: 42.0,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: bIsCellFocused
              ? Colors.amber.withValues(alpha: 0.30)
              : (bIsSelected ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent),
          border: bIsCellFocused
              ? Border.all(color: Colors.amber.shade400, width: 2.0)
              : Border(
                  right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                ),
        ),
        child: Text(
          strCellValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.monoStyle.copyWith(
            color: bIsZap ? Colors.redAccent : (bIsCellFocused ? Colors.amber.shade200 : theme.colorScheme.onSurface),
            decoration: bIsZap ? TextDecoration.lineThrough : TextDecoration.none,
            fontWeight: (bIsSelected || bIsCellFocused) ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );
    }

    final String strKey = '${iRowIndex}_$strFieldName';
    final controller = m_mapCellControllers.putIfAbsent(
      strKey,
      () => TextEditingController(text: strCellValue),
    );

    if (controller.text != strCellValue && !m_bIsDirty) {
      controller.text = strCellValue;
    }

    return Container(
      width: 160.0,
      height: 42.0,
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.cyanAccent, width: 2.0),
      ),
      child: TextField(
        controller: controller,
        enabled: !bIsZap,
        autofocus: true,
        style: context.monoStyle.copyWith(
          color: bIsZap ? Colors.redAccent : Colors.cyanAccent,
          decoration: bIsZap ? TextDecoration.lineThrough : TextDecoration.none,
          fontWeight: FontWeight.bold,
        ),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
          fillColor: Colors.transparent,
          filled: true,
          border: InputBorder.none,
        ),
        onChanged: (_) {
          if (!m_bIsDirty) {
            setState(() => m_bIsDirty = true);
          }
        },
        onSubmitted: (_) {
          _commitRowChanges(iRowIndex);
          setState(() {
            m_iEditingRowIndex = null;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final bool bHasActiveTool = m_activeTab?.strActiveBottomTool != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: GestureDetector(
          // 雙指水平手勢：滑動切換 Tab
          onHorizontalDragEnd: (details) {
            if (m_listTabs.length <= 1) return;
            final int currIdx = m_iActiveTabIndex;
            if (details.primaryVelocity! < -300 && currIdx < m_listTabs.length - 1) {
              setState(() => m_strActiveTabId = m_listTabs[currIdx + 1].strId);
              _updateStatusBarMetrics();
            } else if (details.primaryVelocity! > 300 && currIdx > 0) {
              setState(() => m_strActiveTabId = m_listTabs[currIdx - 1].strId);
              _updateStatusBarMetrics();
            }
          },
          child: Stack(
            children: [
              Column(
                children: [
                  _buildPadTopAppBar(context, theme, craftsmanColors),
                  _buildWorkAreaTabBar(context, theme, craftsmanColors),
                  _buildHeaderShell(context, theme, craftsmanColors),
                  Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                  _buildSmartSeekBar(context, theme, craftsmanColors),
                  Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                  Expanded(
                    child: _buildDataGridWorkplace(context, theme, craftsmanColors),
                  ),
                  if (m_listTabs.isNotEmpty) ...[
                    _buildBottomToolNavigationBar(context, theme, craftsmanColors),
                    Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                  ],
                  _buildPadStatusBar(context, theme),
                ],
              ),

              // 底部工具箱抽屜（Relation Studio 與 Schema Designer）
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                top: bHasActiveTool ? 140.0 : MediaQuery.of(context).size.height,
                bottom: bHasActiveTool ? 32.0 : -MediaQuery.of(context).size.height,
                left: 0.0,
                right: 0.0,
                child: Material(
                  elevation: 16.0,
                  color: theme.cardColor,
                  child: Visibility(
                    visible: bHasActiveTool,
                    maintainState: true,
                    child: _buildActiveBottomToolView(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPadTopAppBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    return Container(
      height: 48.0,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
      child: Row(
        children: [
          Icon(Icons.tablet_mac_rounded, size: 20.0, color: craftsmanColors.m_colorWarmAmber ?? theme.primaryColor),
          const SizedBox(width: 8.0),
          Text(m_language.getValue('TITLE'), style: context.uiBoldStyle.copyWith(fontSize: 14.0)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.note_add_outlined),
            tooltip: m_language.getValue('MENU_NEW_TABLE'),
            onPressed: _handleOpenNewSchema,
          ),
          IconButton(
            icon: const Icon(Icons.folder_open_outlined),
            tooltip: m_language.getValue('MENU_OPEN_EXPLORER'),
            onPressed: _handleOpenEbfDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: m_language.getValue('MENU_SAVE'),
            onPressed: () {
              if (m_activeTab?.iHandle != null && m_activeTab!.iHandle != 0) {
                m_dbService.commit(iHandle: m_activeTab!.iHandle);
                setState(() => m_bIsDirty = false);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => AboutDialogPanel.show(context),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkAreaTabBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    return Container(
      height: 38.0,
      color: theme.scaffoldBackgroundColor,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: m_listTabs.length,
        itemBuilder: (context, idx) {
          final tab = m_listTabs[idx];
          final bool isSelected = tab.strId == m_strActiveTabId;
          return InkWell(
            onTap: () {
              setState(() {
                m_strActiveTabId = tab.strId;
                m_strActiveEbfPath = tab.strFilePath;
                if (tab.strFilePath.isNotEmpty) Directory.current = File(tab.strFilePath).parent.path;
                _updateStatusBarMetrics();
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0),
              decoration: BoxDecoration(
                color: isSelected ? (craftsmanColors.m_colorCardBg ?? theme.cardColor) : theme.scaffoldBackgroundColor,
                border: Border(
                  top: BorderSide(color: isSelected ? theme.colorScheme.primary : Colors.transparent, width: 2.5),
                  right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 1.0),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.table_chart_outlined, size: 16.0, color: isSelected ? theme.primaryColor : Colors.grey),
                  const SizedBox(width: 8.0),
                  Text(tab.strFileName,
                      style: TextStyle(fontSize: 12.0, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                  const SizedBox(width: 10.0),
                  GestureDetector(
                    onTap: () => _closeTab(tab.strId),
                    child: const Icon(Icons.close_rounded, size: 16.0, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeaderShell(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final List<String> lstEdxKeys = m_activeTab?.listEdxKeys ?? <String>[];
    return Container(
      height: 72.0,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      color: craftsmanColors.m_colorCardBg ?? theme.cardColor,
      child: Row(
        children: [
          Expanded(
            child: lstEdxKeys.isEmpty
                ? Center(child: Text(m_language.getValue('NO_EDX_INDEX'), style: context.monoCaptionStyle))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: lstEdxKeys.length,
                    itemBuilder: (context, idx) {
                      final bool isSelected = (idx == m_iActiveSlotIndex) && m_strCurrentSearchMode.startsWith('Seek');
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: InkWell(
                          onTap: () => _switchEdxSlot(idx + 1),
                          child: Container(
                            width: 140.0,
                            padding: const EdgeInsets.all(6.0),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.amber.withValues(alpha: 0.15) : theme.scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(6.0),
                              border: Border.all(
                                  color:
                                      isSelected ? Colors.amber.shade700 : (craftsmanColors.m_colorBorder ?? theme.dividerColor)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Slot ${idx + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.0,
                                    color: isSelected ? Colors.amber.shade900 : null,
                                  ),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  lstEdxKeys[idx],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: context.monoCaptionStyle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartSeekBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final bool bHasActiveTab = m_activeTab != null && m_activeTab!.iHandle != 0;
    return Container(
      height: 48.0,
      color: theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Row(
        children: [
          Icon(Icons.search, size: 20.0, color: craftsmanColors.m_colorWarmAmber ?? theme.primaryColor),
          const SizedBox(width: 8.0),
          Text('$m_strCurrentSearchMode:', style: context.uiBoldStyle.copyWith(fontSize: 12.0)),
          const SizedBox(width: 10.0),
          Expanded(
            child: TextField(
              controller: m_controllerSeekInput,
              focusNode: m_focusNodeSeekInput,
              enabled: bHasActiveTab,
              style: context.uiStyle,
              onSubmitted: (_) => _executeSeek(),
              decoration: InputDecoration(
                hintText: m_language.getValue('SEEK_HINT_INPUT'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                filled: true,
                fillColor: theme.scaffoldBackgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8.0),
          ElevatedButton(
            onPressed: bHasActiveTab ? () => _executeSeek() : null,
            child: const Text('查詢'),
          ),
        ],
      ),
    );
  }

  Widget _buildDataGridWorkplace(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) {
      return Center(child: Text(m_language.getValue('NO_DATASET_LOADED'), style: context.uiStyle));
    }

    final int iHandle = m_activeTab!.iHandle;
    final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
    final List<String> lstHeaders = lstFdt.map((EzField f) => f.name).toList();
    const double dFrozenWidth = 120.0;
    final double dScrollableWidth = lstHeaders.length * 160.0;

    return ValueListenableBuilder<int>(
      valueListenable: m_notifierBufferUpdate,
      builder: (context, _, __) {
        return Stack(
          children: [
            Positioned.fill(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  dragDevices: <ui.PointerDeviceKind>{
                    ui.PointerDeviceKind.touch,
                    ui.PointerDeviceKind.mouse,
                    ui.PointerDeviceKind.trackpad,
                    ui.PointerDeviceKind.stylus,
                  },
                ),
                child: SingleChildScrollView(
                  controller: m_scrollControllerHorizontalBody,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Container(
                    padding: const EdgeInsets.only(left: dFrozenWidth),
                    width: dScrollableWidth + dFrozenWidth,
                    child: Column(
                      children: [
                        // Header
                        SizedBox(
                          height: 40.0,
                          child: Row(
                            children: lstHeaders.map((name) {
                              return Container(
                                width: 160.0,
                                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  border: Border(
                                      right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 0.5)),
                                ),
                                child: Text(name, style: context.monoBoldStyle.copyWith(color: theme.primaryColor)),
                              );
                            }).toList(),
                          ),
                        ),
                        Divider(height: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                        // Records Body
                        Expanded(
                          child: ListView.builder(
                            controller: m_scrollControllerVertical,
                            physics: const BouncingScrollPhysics(),
                            itemExtent: 42.0,
                            itemCount: m_iTotalRecs,
                            itemBuilder: (context, rIdx) {
                              _ensureRowBufferedOptimized(rIdx);
                              final mapRow = m_mapRowCache[rIdx];
                              final bool bIsLoaded = mapRow != null;
                              final bool bIsZap = bIsLoaded ? (mapRow['bIsZap'] as bool) : false;
                              final List<String> values = bIsLoaded ? (mapRow['values'] as List<String>) : <String>[];
                              final bool isSelected = rIdx == m_iSelectedRowIndex;
                              final bool isEditing = rIdx == m_iEditingRowIndex;

                              return InkWell(
                                onTap: () => _selectRowAndSyncEngine(rIdx),
                                onDoubleTap: () {
                                  setState(() {
                                    m_iSelectedRowIndex = rIdx;
                                    m_iCurrentRecNo = rIdx + 1;
                                    m_iEditingRowIndex = rIdx;
                                  });
                                },
                                child: Container(
                                  height: 42.0,
                                  color: isEditing
                                      ? Colors.amber.withValues(alpha: 0.22)
                                      : (isSelected
                                          ? Colors.blue.withValues(alpha: 0.20)
                                          : (rIdx.isEven ? theme.cardColor : theme.scaffoldBackgroundColor)),
                                  child: Row(
                                    children: List.generate(lstHeaders.length, (cIdx) {
                                      final String cellVal = (bIsLoaded && cIdx < values.length) ? values[cIdx] : '';
                                      final bool isCellFocused = isSelected && (cIdx == m_iSelectedColIndex);

                                      return GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _selectRowAndSyncEngine(rIdx, iColIndex: cIdx),
                                        child: _buildCellDisplayOrInput(
                                          iRowIndex: rIdx,
                                          strFieldName: lstHeaders[cIdx],
                                          strCellValue: cellVal,
                                          bIsSelected: isSelected,
                                          bIsCellFocused: isCellFocused,
                                          bIsEditing: isEditing,
                                          bIsZap: bIsZap,
                                          theme: theme,
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // 左側凍結列（含 Commit 綠色確認勾勾與 Zap 切換按鈕）
            Positioned(
              left: 0.0,
              top: 0.0,
              bottom: 0.0,
              width: dFrozenWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  border: Border(right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 1.5)),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 40.0,
                      alignment: Alignment.center,
                      child: Text('# REC', style: context.monoBoldStyle.copyWith(color: theme.primaryColor)),
                    ),
                    Divider(height: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                    Expanded(
                      child: ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemExtent: 42.0,
                        itemCount: m_iTotalRecs,
                        itemBuilder: (context, rIdx) {
                          final isSelected = rIdx == m_iSelectedRowIndex;
                          final bIsZap = m_mapRowCache[rIdx]?['bIsZap'] == true;
                          return InkWell(
                            onTap: () => _selectRowAndSyncEngine(rIdx),
                            child: Container(
                              height: 42.0,
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.2)
                                  : (rIdx.isEven ? theme.cardColor : theme.scaffoldBackgroundColor),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check_circle, color: Colors.green, size: 18.0),
                                    onPressed: () {
                                      _commitRowChanges(rIdx);
                                      setState(() {
                                        m_iEditingRowIndex = null;
                                      });
                                    },
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 4.0),
                                  IconButton(
                                    icon: Icon(bIsZap ? Icons.restore : Icons.delete_outline, size: 18.0, color: Colors.redAccent),
                                    onPressed: () => _toggleDeleteSelectedRow(rIdx),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 6.0),
                                  Text('${rIdx + 1}', style: context.monoBoldStyle.copyWith(fontSize: 12.0)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomToolNavigationBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final String? strActiveTool = m_activeTab?.strActiveBottomTool;
    return Container(
      height: 40.0,
      color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          Icon(Icons.construction_rounded, size: 16.0, color: craftsmanColors.m_colorWarmAmber ?? theme.primaryColor),
          const SizedBox(width: 8.0),
          Text('TOOLCHAIN:', style: context.uiBoldStyle.copyWith(fontSize: 11.0)),
          const SizedBox(width: 12.0),
          ActionChip(
            avatar: const Icon(Icons.hub_rounded, size: 14.0),
            label: Text(m_language.getValue('TAB_RELATION_BUILDER')),
            backgroundColor: strActiveTool == 'relation' ? Colors.amber.withValues(alpha: 0.2) : null,
            onPressed: () => _toggleBottomTool('relation'),
          ),
          const SizedBox(width: 8.0),
          ActionChip(
            avatar: const Icon(Icons.design_services_rounded, size: 14.0),
            label: Text(m_language.getValue('TOOLBOX_MAINTAIN_SCHEMA')),
            backgroundColor: strActiveTool == 'schema' ? Colors.amber.withValues(alpha: 0.2) : null,
            onPressed: () => _toggleBottomTool('schema'),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBottomToolView() {
    if (m_listTabs.isEmpty || m_iActiveTabIndex < 0) return const SizedBox.shrink();
    return IndexedStack(
      index: m_iActiveTabIndex,
      children: m_listTabs.map((tab) {
        return TabToolchainWrapper(
          key: ValueKey('PAD_TOOLCHAIN_${tab.strId}'),
          tab: tab,
          openedTabs: m_listTabs,
          onLoadEbfRequested: _handleOpenEbfDialog,
          onCollapse: () => _toggleBottomTool(null),
          onTableCreated: (String strPath) {
            if (tab.iHandle == 0 || tab.strFilePath.isEmpty) {
              _convertDraftToOpenedEbf(tab.strId, strPath);
            } else {
              _openEbfFile(strPath);
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildPadStatusBar(BuildContext context, ThemeData theme) {
    return Container(
      height: 28.0,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: [
          Text('REC: $m_iCurrentRecNo / $m_iTotalRecs', style: context.monoStyle.copyWith(fontSize: 11.0)),
          const SizedBox(width: 12.0),
          Text('DEL: $m_iDeletedCount', style: context.monoStyle.copyWith(fontSize: 11.0)),
          const Spacer(),
          Text('MODE: $m_strCurrentSearchMode', style: context.monoBoldStyle.copyWith(fontSize: 11.0)),
        ],
      ),
    );
  }
}
