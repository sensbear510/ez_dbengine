/* ===============================================================================================================+
 * FILE: build_relation_view.dart                                                                                 |
 * ---------------------------------------------------------------------------------------------------------------+
 * Copyrights (c) 2026 ezLink.io All rights reserved.                                                             |
 * @ Author : CHI-HSIUNG YANG                                                                                     |
 * ---------------------------------------------------------------------------------------------------------------+
 * 4-STAGE RELATION WIZARD UX VISUAL WORKFLOW:                                                                    |
 * ---------------------------------------------------------------------------------------------------------------+
 *  +-------------------------------------------------------------------------------------------------------------+
 *  | LEFT PANEL (340px Config Wizard)                 | RIGHT PANEL (Topology & Live DataGrid Preview)           |
 *  +--------------------------------------------------+----------------------------------------------------------+
 *  | [Stage 1: View Identity & Join Mode Selection]   | RELATION TOPOLOGY MAP                                    |
 *  |   - Specify View Name (e.g., CustomerOrdersView) |   [customer.ebf] (Master)                                |
 *  |   - Select Driving Master Table (Index 0)        |         │ (TAG_MASTER_KEY == TAG_CHILD_KEY)              |
 *  |   - Select Linked Child Table (Index 1)          |         ▼                                                |
 *  |   - Choose Join Mode: LEFT JOIN vs INNER JOIN    |   [orders.ebf]   (Child) [LEFT JOIN]                     |
 *  |                                                  | ──────────────────────────────────────────────────────── |
 *  | [Stage 2: Strict 1:1 Tag Geometry Mapping]       | LIVE STRUCTURED DATAGRID PREVIEW                         |
 *  |   - Select Master EDX Index Tag                  | +-------+-------------+--------------+-----------------+ |
 *  |   - Select Target Child EDX Index Tag            | | REC#  | CUST_ID     | CUST_NAME    | ORDER_NO        | |
 *  |   - Perform 1:1 Geometry Alignment Audit         | +-------+-------------+--------------+-----------------+ |
 *  |                                                  | | 1     | C000000001  | ACME Corp    | ORD-2026-0001   | |
 *  | [Stage 3: Field Projection Checklist]            | | 2     | C000000002  | Globex Inc   |               * | |
 *  |   - Check/Uncheck individual Master/Child fields | +-------+-------------+--------------+-----------------+ |
 *  |                                                  | (* Blank Padding rendered on missing child record)       |
 *  | [Stage 4: Execution & Persistence Actions]       |                                                          |
 *  |   - [Build View] Spawn active in-memory handle   |                                                          |
 *  |   - [Save .ERL] Export layout descriptor to file |                                                          |
 *  +--------------------------------------------------+----------------------------------------------------------+ 
 *  --------------------------------------------------------------------------------------------------------------|
 *  Workbench Panel for Building, Saving, Loading, and Previewing Relation Views (.ERL).                          |
 *  Virtualized On-Demand Chunk Buffer Architecture Aligned with MainPage.                                        |
 * ===============================================================================================================+
 */

import 'dart:math' as math;
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/db_service.dart';
import '../../../services/ez_dbengine.dart';
import '../../../theme/app_theme.dart';
import '../../../toolbox/ez_notification.dart';
import '../../../toolbox/ez_output.dart';
import '../../../toolbox/language.dart';
import '../../../toolbox/ebf_tab_context.dart';

/// Model for field projection check items
class RlFieldProjectionItem {
  final int ebfIndex;
  final String ebfFileName;
  final String fieldName;
  final String fieldType;
  final int fieldLen;
  bool isSelected;
  String aliasName;

  RlFieldProjectionItem({
    required this.ebfIndex,
    required this.ebfFileName,
    required this.fieldName,
    required this.fieldType,
    required this.fieldLen,
    this.isSelected = true,
    required this.aliasName,
  });
}

class BuildRelationView extends StatefulWidget {
  final List<EbfTabContext> openedTabs;
  final EbfTabContext tab; // Bound exclusively to this tab instance
  final VoidCallback? onCollapse;

  const BuildRelationView({
    super.key,
    required this.openedTabs,
    required this.tab,
    this.onCollapse,
  });

  @override
  State<BuildRelationView> createState() => _BuildRelationViewState();
}

class _BuildRelationViewState extends State<BuildRelationView> {
  final DbService m_dbService = DbService.instance;
  final Language m_language = Language.instance;

  late final TextEditingController m_controllerViewName;
  late final TextEditingController m_controllerMasterSeek;

  int m_iJoinMode = 0; // 0: LEFT JOIN, 1: INNER JOIN

  EbfTabContext? m_selectedMasterTab;
  EbfTabContext? m_selectedSlaveTab;

  String? m_selectedMasterTagName;
  String? m_selectedSlaveTagName;

  final List<RlFieldProjectionItem> m_listProjections = <RlFieldProjectionItem>[];

  // Active Relation View execution states
  int m_hActiveRelation = 0;
  bool m_bIsViewActive = false;

  // Virtualized Dynamic Chunk Buffer States (Aligned with MainPage)
  static const double kRowHeight = 32.0;
  static const double kHeaderHeight = 36.0;
  static const int kChunkSize = 200;

  int m_iTotalRelationRecords = 0;
  final Map<int, EzRecordReader> m_mapRowCache = <int, EzRecordReader>{};
  final Set<int> m_setLoadingChunks = <int>{};

  // Data Preview Grid Selection Light-Bar Row Cursor & Focus Node
  int m_iSelectedRelationRowIndex = 0;
  final FocusNode m_gridFocusNode = FocusNode();

  final ScrollController m_scrollH = ScrollController();
  final ScrollController m_scrollV = ScrollController();

  @override
  void initState() {
    super.initState();
    m_controllerViewName = TextEditingController(text: 'RL_VIEW_01');
    m_controllerMasterSeek = TextEditingController();

    // Default Master Tab directly to this toolchain's owned tab
    m_selectedMasterTab = widget.tab;

    // Do not auto-select slave tab to prevent auto-populating fields
    m_selectedSlaveTab = null;

    _rebuildFieldProjections();
  }

  @override
  void dispose() {
    m_controllerViewName.dispose();
    m_controllerMasterSeek.dispose();
    m_scrollH.dispose();
    m_scrollV.dispose();
    m_gridFocusNode.dispose();
    _destroyActiveRelationView();
    super.dispose();
  }

  /// Unified handler for Relation DataGrid cursor navigation and Master EBF cursor synchronization
  void _navigateRelationRowSelection({
    bool? bMoveDown,
    bool bToHome = false,
    bool bToEnd = false,
  }) {
    if (!m_bIsViewActive || m_iTotalRelationRecords <= 0) return;
    if (m_selectedMasterTab == null || m_selectedMasterTab!.iHandle == 0) return;

    final int iMasterHandle = m_selectedMasterTab!.iHandle;
    final String strMasterTag = m_selectedMasterTagName ?? '';

    int iTargetIndex = m_iSelectedRelationRowIndex;

    if (bToHome) {
      iTargetIndex = 0;
    } else if (bToEnd) {
      iTargetIndex = m_iTotalRelationRecords - 1;
    } else if (bMoveDown != null) {
      if (bMoveDown) {
        if (iTargetIndex < m_iTotalRelationRecords - 1) {
          iTargetIndex++;
        }
      } else {
        if (iTargetIndex > 0) {
          iTargetIndex--;
        }
      }
    }

    if (iTargetIndex != m_iSelectedRelationRowIndex || bToHome || bToEnd) {
      setState(() {
        m_iSelectedRelationRowIndex = iTargetIndex;
      });

      // Synchronize C engine Master EBF cursor (1-based) with current active Master Tag
      m_dbService.goTo(
        iTargetIndex + 1,
        iHandle: iMasterHandle,
        tagName: strMasterTag,
      );

      // Ensure corresponding Chunk is loaded and kept visible in viewport
      _ensureRowBuffered(iTargetIndex);
      _ensureRowVisible(iTargetIndex);
    }
  }

  /// Synchronize C engine Master cursor when a row is clicked
  void _selectRelationRow(int index) {
    if (m_selectedMasterTab != null && m_selectedMasterTab!.iHandle != 0) {
      final String strMasterTag = m_selectedMasterTagName ?? '';
      m_dbService.goTo(
        index + 1,
        iHandle: m_selectedMasterTab!.iHandle,
        tagName: strMasterTag,
      );
    }
    setState(() {
      m_iSelectedRelationRowIndex = index;
    });
    if (m_gridFocusNode.canRequestFocus) {
      m_gridFocusNode.requestFocus();
    }
  }

  void _clearDataBuffer() {
    m_mapRowCache.clear();
    m_setLoadingChunks.clear();
  }

  void _destroyActiveRelationView() {
    if (m_hActiveRelation != 0) {
      m_dbService.rlDestroyView(m_hActiveRelation);
      m_hActiveRelation = 0;
      m_bIsViewActive = false;
      _clearDataBuffer();
    }
  }

  /// Helper to check if a field is included inside an active EDX tag expression
  bool _isFieldInTag(EbfTabContext? tab, String? tagName, String fieldName) {
    if (tab == null || tagName == null || tagName.isEmpty) return false;
    for (final String keyItem in tab.listEdxKeys) {
      if (keyItem.startsWith(tagName)) {
        final int startParen = keyItem.indexOf('(');
        final int endParen = keyItem.indexOf(')');
        if (startParen != -1 && endParen != -1 && endParen > startParen) {
          final String inside = keyItem.substring(startParen + 1, endParen);
          final List<String> fields = inside.split(',').map((s) => s.trim()).toList();
          if (fields.contains(fieldName)) return true;
        }
      }
    }
    return false;
  }

  /// Rebuilds selectable field projection list and appends (M) / (C) Key tags
  void _rebuildFieldProjections() {
    setState(() {
      m_listProjections.clear();

      // 1. Populate Master EBF fields
      if (m_selectedMasterTab != null && m_selectedMasterTab!.iHandle != 0) {
        final List<EzField> masterFields = m_dbService.getFdt(iHandle: m_selectedMasterTab!.iHandle);
        for (final f in masterFields) {
          final bool bIsMasterKey = _isFieldInTag(m_selectedMasterTab, m_selectedMasterTagName, f.name);
          final String keyMarker = bIsMasterKey ? ' (M)' : '';

          m_listProjections.add(
            RlFieldProjectionItem(
              ebfIndex: 0,
              ebfFileName: m_selectedMasterTab!.strFileName,
              fieldName: f.name,
              fieldType: f.type,
              fieldLen: f.len,
              isSelected: true,
              aliasName: '${f.name}$keyMarker',
            ),
          );
        }
      }

      // 2. Populate Child EBF fields
      if (m_selectedSlaveTab != null && m_selectedSlaveTab!.iHandle != 0) {
        final List<EzField> slaveFields = m_dbService.getFdt(iHandle: m_selectedSlaveTab!.iHandle);
        final String slavePrefix = m_selectedSlaveTab!.strFileName.split('.').first;
        for (final f in slaveFields) {
          final bool bIsChildKey = _isFieldInTag(m_selectedSlaveTab, m_selectedSlaveTagName, f.name);
          final String keyMarker = bIsChildKey ? ' (C)' : '';

          m_listProjections.add(
            RlFieldProjectionItem(
              ebfIndex: 1,
              ebfFileName: m_selectedSlaveTab!.strFileName,
              fieldName: f.name,
              fieldType: f.type,
              fieldLen: f.len,
              isSelected: true,
              aliasName: '${slavePrefix}_${f.name}$keyMarker',
            ),
          );
        }
      }
    });
  }

  /// On-Demand Chunk Buffer Loader strictly utilizing C-engine ez_rl_get_record_vector
  void _ensureRowBuffered(int targetRowIndex) {
    if (m_mapRowCache.containsKey(targetRowIndex)) return;

    final int chunkId = targetRowIndex ~/ kChunkSize;
    if (m_setLoadingChunks.contains(chunkId)) return;
    m_setLoadingChunks.add(chunkId);

    Future.microtask(() {
      if (m_mapRowCache.containsKey(targetRowIndex)) {
        m_setLoadingChunks.remove(chunkId);
        return;
      }

      if (m_selectedMasterTab == null || m_selectedMasterTab!.iHandle == 0) {
        m_setLoadingChunks.remove(chunkId);
        return;
      }

      // 1. Ensure active Relation View handle exists before fetching stitched records
      if (m_hActiveRelation == 0) {
        _executeBuildView();
      }

      if (m_hActiveRelation == 0) {
        m_setLoadingChunks.remove(chunkId);
        return;
      }

      final int iMasterHandle = m_selectedMasterTab!.iHandle;
      final int startRowIndex = chunkId * kChunkSize;
      final int startRecNo = startRowIndex + 1;

      // 2. Position Master EBF physical cursor so C-engine relation iterator aligns at startRecNo

      m_dbService.goTo(
        startRecNo,
        iHandle: iMasterHandle,
        tagName: m_selectedMasterTagName ?? '',
      );

      // 3. Compute total stitched record payload size from active field projections
      final List<RlFieldProjectionItem> selectedItems = m_listProjections.where((i) => i.isSelected).toList();
      int recordSize = 0;
      for (final item in selectedItems) {
        recordSize += item.fieldLen;
      }
      if (recordSize == 0) recordSize = 128;

      // 4. Fetch stitched record vector strictly via C-engine ez_rl_get_record_vector
      final List<EzRecordReader> readers = m_dbService.rlGetRecordVector(
        m_hActiveRelation,
        recordSize,
        count: kChunkSize,
      );

      for (int i = 0; i < readers.length; i++) {
        m_mapRowCache[startRowIndex + i] = readers[i];
      }

      if (mounted) {
        setState(() {});
      }

      m_setLoadingChunks.remove(chunkId);
    });
  }

  /// Executes Master Key Seek via EDX Index, buffers target chunk, and scrolls viewport
  void _executeMasterKeySeek() {
    final String strSeekKey = m_controllerMasterSeek.text.trim();
    if (strSeekKey.isEmpty) return;

    if (m_selectedMasterTab == null || m_selectedMasterTab!.iHandle == 0) return;
    if (m_selectedMasterTagName == null || m_selectedMasterTagName!.isEmpty) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('NOTIF_INVALID_TAG_TITLE'),
        message: m_language.getValue('NOTIF_INVALID_TAG_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return;
    }

    final int iMasterHandle = m_selectedMasterTab!.iHandle;

    if (m_hActiveRelation == 0) {
      _executeBuildView();
    }

    // 1. Perform C-engine EDX Seek against Master EBF
    final bool bFound = m_dbService.seekByName(
      m_selectedMasterTagName!,
      <String>[strSeekKey],
      iHandle: iMasterHandle,
    );

    if (bFound) {
      final int iFoundRecNo = m_dbService.getRecNo(iHandle: iMasterHandle);
      final int targetRowIndex = iFoundRecNo - 1;

      // 2. Load chunk for target row
      _ensureRowBuffered(targetRowIndex);

      // 3. Highlight target row
      setState(() {
        m_iSelectedRelationRowIndex = targetRowIndex;
        m_bIsViewActive = true;
      });

      // 4. Scroll Viewport directly to target row position
      _ensureRowVisible(targetRowIndex);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (m_gridFocusNode.canRequestFocus) {
          m_gridFocusNode.requestFocus();
        }
      });

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('NOTIF_EBF_LOADED_TITLE'),
        message: 'Found Master Key: [$strSeekKey] at Master REC #$iFoundRecNo (Row #${targetRowIndex + 1})',
        icon: Icons.check_circle_outline_rounded,
        accentColor: Colors.amber.shade800,
      );
    } else {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('NOTIF_SEARCH_NOT_FOUND_TITLE'),
        message: '${m_language.getValue('NOTIF_SEARCH_NOT_FOUND_MSG')} [$strSeekKey] (Tag: $m_selectedMasterTagName)',
        icon: Icons.search_off_rounded,
        accentColor: Colors.orange,
      );
    }
  }

  /// Generates standardized .ERL naming rule: ebfname_masteredxname+_+slaveedxname.erl
  String _generateStandardErlFileName() {
    final String masterName = m_selectedMasterTab?.strFileName.replaceAll(RegExp(r'\.ebf$', caseSensitive: false), '') ?? 'master';
    final String masterEdx = m_selectedMasterTagName?.trim() ?? 'NONE';
    final String slaveEdx = m_selectedSlaveTagName?.trim() ?? 'NONE';

    return '${masterName}_$masterEdx+_+$slaveEdx.erl';
  }

  /// Builds RlViewDesc data structure
  RlViewDesc? _buildViewDescriptor() {
    if (m_selectedMasterTab == null || m_selectedMasterTab!.iHandle == 0) return null;

    final String viewName = m_controllerViewName.text.trim().isEmpty ? 'RL_VIEW' : m_controllerViewName.text.trim();
    final List<int> ebfHandles = <int>[m_selectedMasterTab!.iHandle];
    if (m_selectedSlaveTab != null && m_selectedSlaveTab!.iHandle != 0) {
      ebfHandles.add(m_selectedSlaveTab!.iHandle);
    }

    final List<RlNode> selectedNodes = m_listProjections
        .where((item) => item.isSelected)
        .map((item) => RlNode(
              ebfIndex: item.ebfIndex,
              fieldName: item.fieldName,
              aliasName: item.aliasName.isEmpty ? item.fieldName : item.aliasName,
            ))
        .toList();

    final List<RlLink> links = <RlLink>[];
    if (m_selectedSlaveTab != null && m_selectedSlaveTagName != null) {
      links.add(
        RlLink(
          parentEbfIndex: 0,
          childEbfIndex: 1,
          parentFkOffsets: <int>[0],
          parentFkLens: <int>[10],
          childTagName: m_selectedSlaveTagName!,
        ),
      );
    }

    return RlViewDesc(
      relationName: viewName,
      joinMode: m_iJoinMode,
      ebfHandles: ebfHandles,
      nodes: selectedNodes,
      links: links,
    );
  }

  /// 1. Action: Build Relation View
  void _executeBuildView() {
    final RlViewDesc? desc = _buildViewDescriptor();
    if (desc == null) return;

    _destroyActiveRelationView();
    final int hRel = m_dbService.rlBuildView(desc);

    if (hRel != 0) {
      setState(() {
        m_hActiveRelation = hRel;
        m_bIsViewActive = false;
      });

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('REL_NOTIF_BUILD_SUCCESS_TITLE'),
        message:
            '${m_language.getValue('REL_NOTIF_BUILD_SUCCESS_MSG')} [${desc.relationName}] (#0x${hRel.toRadixString(16).toUpperCase()})',
        icon: Icons.check_circle_outline_rounded,
        accentColor: Colors.amber.shade800,
      );
    } else {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('REL_NOTIF_BUILD_FAIL_TITLE'),
        message: m_language.getValue('REL_NOTIF_BUILD_FAIL_MSG'),
        icon: Icons.error_outline_rounded,
        accentColor: Colors.red,
      );
    }
  }

  /// 2. Action: Save .ERL File
  Future<void> _executeSaveErlFile() async {
    final RlViewDesc? desc = _buildViewDescriptor();
    if (desc == null) return;

    final String defaultFileName = _generateStandardErlFileName();
    final String? strSavePath = await FilePicker.platform.saveFile(
      dialogTitle: m_language.getValue('REL_DIALOG_SAVE_TITLE'),
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: <String>['erl'],
    );

    if (!mounted) return;

    if (strSavePath != null) {
      final int iStatus = m_dbService.rlSaveViewFile(desc, strSavePath);
      if (iStatus == 0) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('REL_NOTIF_SAVE_SUCCESS_TITLE'),
          message: '${m_language.getValue('REL_NOTIF_SAVE_SUCCESS_MSG')} $strSavePath',
          icon: Icons.save_rounded,
          accentColor: Colors.amber.shade800,
        );
      }
    }
  }

  /// 3. Action: Load .ERL File
  Future<void> _executeLoadErlFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['erl'],
    );

    if (!mounted) return;

    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      final String strPath = result.files.single.path!;
      final List<int> handles = widget.openedTabs.map((t) => t.iHandle).where((h) => h != 0).toList();

      if (handles.isEmpty) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('REL_NOTIF_LOAD_FAIL_TITLE'),
          message: m_language.getValue('REL_NOTIF_LOAD_FAIL_MSG'),
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return;
      }

      _destroyActiveRelationView();
      final int hRel = m_dbService.rlLoadViewFile(strPath, handles);

      if (hRel != 0) {
        setState(() {
          m_hActiveRelation = hRel;
          m_bIsViewActive = false;
        });

        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('REL_NOTIF_LOAD_SUCCESS_TITLE'),
          message: '${m_language.getValue('REL_NOTIF_LOAD_SUCCESS_MSG')} $strPath',
          icon: Icons.folder_open_rounded,
          accentColor: Colors.amber.shade800,
        );
      } else {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('REL_NOTIF_COMPAT_FAIL_TITLE'),
          message: m_language.getValue('REL_NOTIF_COMPAT_FAIL_MSG'),
          icon: Icons.gpp_bad_rounded,
          accentColor: Colors.redAccent,
        );
      }
    }
  }

  /// 4. Action: Activate View & Initialize DataGrid
  void _executeActivateView() {
    _clearDataBuffer();
    setState(() {
      m_iSelectedRelationRowIndex = 0;
    });

    if (m_hActiveRelation == 0) {
      _executeBuildView();
    }

    if (m_hActiveRelation == 0 || m_selectedMasterTab == null) return;

    final int totalMasterRecs = m_dbService.getRecordCount(iHandle: m_selectedMasterTab!.iHandle);

    setState(() {
      m_iTotalRelationRecords = totalMasterRecs;
      m_iSelectedRelationRowIndex = 0;
      m_bIsViewActive = true;
    });

    _ensureRowBuffered(0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (m_gridFocusNode.canRequestFocus) {
        m_gridFocusNode.requestFocus();
      }
    });

    ezOutput('[Relation Studio] Activated View (Total: $totalMasterRecs records).');
  }

  /// Auto-scroll vertical viewport to keep active light-bar row visible
  void _ensureRowVisible(int index) {
    if (!m_scrollV.hasClients) return;
    final double targetOffset = index * kRowHeight;
    final double currentOffset = m_scrollV.offset;
    final double viewportHeight = m_scrollV.position.viewportDimension;

    if (targetOffset < currentOffset) {
      m_scrollV.jumpTo(targetOffset);
    } else if (targetOffset + kRowHeight > currentOffset + viewportHeight) {
      m_scrollV.jumpTo(targetOffset + kRowHeight - viewportHeight);
    }
  }

  /// Synchronizes C-engine Master cursor on collapse
  void _handleCollapseWithCursorSync() {
    if (m_selectedMasterTab != null && m_selectedMasterTab!.iHandle != 0) {
      m_dbService.goTo(m_iSelectedRelationRowIndex + 1, iHandle: m_selectedMasterTab!.iHandle);
    }
    if (widget.onCollapse != null) {
      widget.onCollapse!();
    }
  }

  /// Helper widget for rendering Master / Child table selection dropdowns
  Widget _buildTableDropdown({
    required String strLabelText,
    required EbfTabContext? selectedTab,
    required ValueChanged<EbfTabContext?> onChanged,
  }) {
    return DropdownButtonFormField<EbfTabContext>(
      initialValue: selectedTab,
      isDense: true,
      decoration: InputDecoration(
        labelText: strLabelText,
        isDense: true,
      ),
      items: widget.openedTabs
          .map((tab) => DropdownMenuItem<EbfTabContext>(
                value: tab,
                child: Text(
                  tab.strFileName,
                  style: const TextStyle(fontSize: 11.0),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  /// Unified Dark-Amber Craftsman Button Style Supplier
  ButtonStyle _getDarkAmberButtonStyle(BuildContext context, CraftsmanColors craftsmanColors, {bool bHighlightBorder = false}) {
    final Color amberColor = craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade700;
    final ThemeData theme = Theme.of(context);

    return ElevatedButton.styleFrom(
      backgroundColor: theme.cardColor,
      foregroundColor: amberColor,
      elevation: 0.0,
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: amberColor,
        width: bHighlightBorder ? 1.5 : 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final Color amberColor = craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade700;

    return Row(
      children: <Widget>[
        // Left Configuration Panel
        Container(
          width: 440.0,
          color: theme.cardColor,
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(m_language.getValue('REL_PANEL_TITLE'), style: context.uiBoldStyle.copyWith(fontSize: 13.0)),
                  if (widget.onCollapse != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 26.0),
                      onPressed: _handleCollapseWithCursorSync,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 8.0),

              // View Name Input
              TextField(
                controller: m_controllerViewName,
                style: context.uiStyle,
                decoration: InputDecoration(
                  labelText: m_language.getValue('REL_VIEW_NAME_LABEL'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8.0),

              // Section 1: Tables & Join Mode
              Text(m_language.getValue('REL_SECTION_TABLES_JOIN'),
                  style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: amberColor)),
              const SizedBox(height: 4.0),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _buildTableDropdown(
                      strLabelText: m_language.getValue('REL_MASTER_EBF_LABEL'),
                      selectedTab: m_selectedMasterTab,
                      onChanged: (val) {
                        setState(() {
                          m_selectedMasterTab = val;
                          _rebuildFieldProjections();
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: _buildTableDropdown(
                      strLabelText: m_language.getValue('REL_CHILD_EBF_LABEL'),
                      selectedTab: m_selectedSlaveTab,
                      onChanged: (val) {
                        setState(() {
                          m_selectedSlaveTab = val;
                          _rebuildFieldProjections();
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6.0),

              // SegmentedButton
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return amberColor.withValues(alpha: 0.2);
                      }
                      return theme.cardColor;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
                      if (states.contains(WidgetState.selected)) {
                        return amberColor;
                      }
                      return theme.colorScheme.onSurface.withValues(alpha: 0.6);
                    }),
                    side: WidgetStateProperty.all(
                      BorderSide(color: amberColor, width: 1.0),
                    ),
                  ),
                  segments: const <ButtonSegment<int>>[
                    ButtonSegment<int>(
                        value: 0, label: Text('LEFT JOIN', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold))),
                    ButtonSegment<int>(
                        value: 1, label: Text('INNER JOIN', style: TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold))),
                  ],
                  selected: <int>{m_iJoinMode},
                  onSelectionChanged: (Set<int> newSelection) {
                    setState(() {
                      m_iJoinMode = newSelection.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 8.0),

              // Section 2: EDX Key Pairing
              Text(m_language.getValue('REL_SECTION_EDX_KEYS'),
                  style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: amberColor)),
              const SizedBox(height: 4.0),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: m_selectedMasterTagName,
                      isDense: true,
                      decoration: InputDecoration(labelText: m_language.getValue('REL_MASTER_EDX_LABEL'), isDense: true),
                      items: (m_selectedMasterTab?.listEdxKeys ?? <String>[])
                          .map((k) =>
                              DropdownMenuItem(value: k.split(' ').first, child: Text(k, style: const TextStyle(fontSize: 10.0))))
                          .toList(),
                      onChanged: (v) => setState(() {
                        m_selectedMasterTagName = v;
                        _rebuildFieldProjections();
                      }),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: m_selectedSlaveTagName,
                      isDense: true,
                      decoration: InputDecoration(labelText: m_language.getValue('REL_CHILD_EDX_LABEL'), isDense: true),
                      items: (m_selectedSlaveTab?.listEdxKeys ?? <String>[])
                          .map((k) =>
                              DropdownMenuItem(value: k.split(' ').first, child: Text(k, style: const TextStyle(fontSize: 10.0))))
                          .toList(),
                      onChanged: (v) => setState(() {
                        m_selectedSlaveTagName = v;
                        _rebuildFieldProjections();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8.0),

              // Section 3: Field Projections Checklist
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(m_language.getValue('REL_SECTION_PROJECTIONS'),
                      style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: amberColor)),
                  Row(
                    children: <Widget>[
                      InkWell(
                        onTap: () => setState(() {
                          for (final i in m_listProjections) {
                            i.isSelected = true;
                          }
                        }),
                        child: Text(m_language.getValue('BTN_SELECT_ALL'), style: TextStyle(fontSize: 10.0, color: amberColor)),
                      ),
                      const SizedBox(width: 8.0),
                      InkWell(
                        onTap: () => setState(() {
                          for (final i in m_listProjections) {
                            i.isSelected = false;
                          }
                        }),
                        child: Text(m_language.getValue('BTN_DESELECT_ALL'),
                            style: const TextStyle(fontSize: 10.0, color: Colors.grey)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4.0),

              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                    borderRadius: BorderRadius.circular(4.0),
                  ),
                  child: ListView.builder(
                    itemCount: m_listProjections.length,
                    itemBuilder: (context, index) {
                      final item = m_listProjections[index];
                      return Tooltip(
                        message: '${item.ebfFileName} -> ${item.fieldName} (${item.fieldType}, ${item.fieldLen}B)',
                        waitDuration: const Duration(milliseconds: 200),
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                            decoration: BoxDecoration(
                              border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
                            ),
                            child: Row(
                              children: <Widget>[
                                Checkbox(
                                  value: item.isSelected,
                                  activeColor: amberColor,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) => setState(() => item.isSelected = v ?? false),
                                ),
                                Expanded(
                                  child: Text(
                                    '${item.aliasName} (${item.fieldType}, ${item.fieldLen}B)',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    softWrap: false,
                                    style: context.monoStyle.copyWith(
                                      fontSize: 11.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 8.0),

              // Bottom 4-Action Button Toolbar Matrix
              Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          style: _getDarkAmberButtonStyle(context, craftsmanColors),
                          onPressed: _executeBuildView,
                          icon: Icon(Icons.hub_rounded, size: 14.0, color: amberColor),
                          label: Text(m_language.getValue('REL_BTN_BUILD'),
                              style: TextStyle(fontSize: 11.0, color: amberColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: _getDarkAmberButtonStyle(context, craftsmanColors),
                          onPressed: _executeSaveErlFile,
                          icon: Icon(Icons.save_rounded, size: 14.0, color: amberColor),
                          label: Text(m_language.getValue('REL_BTN_SAVE'),
                              style: TextStyle(fontSize: 11.0, color: amberColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          style: _getDarkAmberButtonStyle(context, craftsmanColors),
                          onPressed: _executeLoadErlFile,
                          icon: Icon(Icons.folder_open_rounded, size: 14.0, color: amberColor),
                          label: Text(m_language.getValue('REL_BTN_LOAD'),
                              style: TextStyle(fontSize: 11.0, color: amberColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 6.0),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: _getDarkAmberButtonStyle(context, craftsmanColors, bHighlightBorder: true),
                          onPressed: _executeActivateView,
                          icon: Icon(Icons.play_arrow_rounded, size: 14.0, color: amberColor),
                          label: Text(m_language.getValue('REL_BTN_ACTIVATE'),
                              style: TextStyle(fontSize: 11.0, color: amberColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Right Preview Panel: Stitched Read-Only DataGrid
        Expanded(
          child: Container(
            color: theme.scaffoldBackgroundColor,
            child: !m_bIsViewActive
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.hub_outlined, size: 64.0, color: theme.dividerColor),
                        const SizedBox(height: 12.0),
                        Text(
                          m_language.getValue('REL_PREVIEW_HINT'),
                          style: context.uiStyle.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: <Widget>[
                      // Master Key Seek Action Toolbar
                      Container(
                        height: 44.0,
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                        color: theme.cardColor,
                        child: Row(
                          children: <Widget>[
                            Text(
                              '${m_language.getValue('REL_PREVIEW_TITLE')} ($m_iTotalRelationRecords REC)',
                              style: context.monoBoldStyle.copyWith(color: amberColor, fontSize: 11.0),
                            ),
                            const SizedBox(width: 16.0),
                            Icon(Icons.vpn_key_rounded, size: 15.0, color: Colors.amber.shade800),
                            const SizedBox(width: 6.0),
                            Text('Master Key Seek:',
                                style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: Colors.amber.shade800)),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: TextField(
                                controller: m_controllerMasterSeek,
                                style: context.uiStyle.copyWith(fontSize: 11.0),
                                onSubmitted: (_) => _executeMasterKeySeek(),
                                decoration: InputDecoration(
                                  hintText: 'Enter Master Key...',
                                  hintStyle: context.uiStyle
                                      .copyWith(fontSize: 11.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                                  filled: true,
                                  fillColor: theme.scaffoldBackgroundColor,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4.0), borderSide: BorderSide.none),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8.0),
                            // Seek Action Button
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
                              ),
                              onPressed: _executeMasterKeySeek,
                              icon: const Icon(Icons.search_rounded, size: 14.0),
                              label: Text('Seek', style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: Colors.white)),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1.0, thickness: 1.0),

                      // DataGrid Container
                      Expanded(
                          child: Focus(
                        focusNode: m_gridFocusNode,
                        onKeyEvent: (FocusNode node, KeyEvent event) {
                          if (event is KeyDownEvent || event is KeyRepeatEvent) {
                            final key = event.logicalKey;

                            // Down
                            if (key == LogicalKeyboardKey.arrowDown) {
                              _navigateRelationRowSelection(bMoveDown: true);
                              return KeyEventResult.handled;
                            }
                            // Up
                            if (key == LogicalKeyboardKey.arrowUp) {
                              _navigateRelationRowSelection(bMoveDown: false);
                              return KeyEventResult.handled;
                            }
                            // Home (Jump to first record)
                            if (key == LogicalKeyboardKey.home) {
                              _navigateRelationRowSelection(bToHome: true);
                              return KeyEventResult.handled;
                            }
                            // End (Jump to last record)
                            if (key == LogicalKeyboardKey.end) {
                              _navigateRelationRowSelection(bToEnd: true);
                              return KeyEventResult.handled;
                            }
                            // Horizontal pan
                            if (key == LogicalKeyboardKey.arrowRight) {
                              if (m_scrollH.hasClients) {
                                final double target = (m_scrollH.offset + 140.0).clamp(0.0, m_scrollH.position.maxScrollExtent);
                                m_scrollH.animateTo(target, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
                              }
                              return KeyEventResult.handled;
                            }
                            if (key == LogicalKeyboardKey.arrowLeft) {
                              if (m_scrollH.hasClients) {
                                final double target = (m_scrollH.offset - 140.0).clamp(0.0, m_scrollH.position.maxScrollExtent);
                                m_scrollH.animateTo(target, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
                              }
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: _buildRelationDataGrid(theme, craftsmanColors),
                      )),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  /// Read-Only Stitched Relation DataGrid Renderer Aligned with MainPage
  Widget _buildRelationDataGrid(ThemeData theme, CraftsmanColors craftsmanColors) {
    final List<RlFieldProjectionItem> selectedFields = m_listProjections.where((i) => i.isSelected).toList();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double calculatedContentWidth = selectedFields.length * 140.0 + 60.0;
        final double finalWidth = math.max(calculatedContentWidth, constraints.maxWidth);

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: <PointerDeviceKind>{
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: Scrollbar(
            controller: m_scrollH,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 10.0,
            child: SingleChildScrollView(
              controller: m_scrollH,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: finalWidth,
                child: Column(
                  children: <Widget>[
                    // 1. Header Row
                    Container(
                      height: kHeaderHeight,
                      color: craftsmanColors.m_colorCardBg ?? theme.cardColor,
                      child: Row(
                        children: <Widget>[
                          Container(
                            width: 50.0,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border:
                                  Border(right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 0.5)),
                            ),
                            child: Text('#', style: context.monoBoldStyle.copyWith(color: theme.colorScheme.primary)),
                          ),
                          ...selectedFields.map(
                            (f) => Container(
                              width: 140.0,
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                border: Border(
                                    right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 0.5)),
                              ),
                              child: Tooltip(
                                message: 'Source: ${f.ebfFileName}\nField: ${f.fieldName}',
                                waitDuration: const Duration(milliseconds: 200),
                                child: Text(
                                  f.aliasName,
                                  maxLines: 1,
                                  overflow: TextOverflow.clip,
                                  softWrap: false,
                                  style: context.monoBoldStyle.copyWith(color: theme.colorScheme.primary),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),

                    // 2. On-Demand Virtualized Data Rows
                    Expanded(
                      child: Scrollbar(
                        controller: m_scrollV,
                        thumbVisibility: true,
                        trackVisibility: true,
                        thickness: 10.0,
                        child: ListView.builder(
                          controller: m_scrollV,
                          itemExtent: kRowHeight,
                          itemCount: m_iTotalRelationRecords,
                          itemBuilder: (context, index) {
                            final bool bIsSelected = (index == m_iSelectedRelationRowIndex);

                            // On-demand chunk loader
                            _ensureRowBuffered(index);

                            final EzRecordReader? reader = m_mapRowCache[index];

                            int currentOffset = 0;
                            final Color rowBgColor = bIsSelected
                                ? Colors.blue.withValues(alpha: 0.30)
                                : (index.isEven ? theme.cardColor : theme.scaffoldBackgroundColor);

                            return InkWell(
                              onTap: () => _selectRelationRow(index),
                              child: Container(
                                height: kRowHeight,
                                decoration: BoxDecoration(
                                  color: rowBgColor,
                                  border: Border(
                                    bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    // Row Sequence Number Cell (Real RecNo)
                                    Container(
                                      width: 50.0,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        border: Border(right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
                                      ),
                                      child: Text(
                                        '${index + 1}',
                                        style: context.monoCaptionStyle.copyWith(
                                          fontWeight: bIsSelected ? FontWeight.bold : FontWeight.normal,
                                          color:
                                              bIsSelected ? Colors.amberAccent : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                        ),
                                      ),
                                    ),
                                    // Stitched Column Cells
                                    ...selectedFields.map((field) {
                                      final String val = reader != null ? reader.stringAt(currentOffset, field.fieldLen) : '...';
                                      currentOffset += field.fieldLen;

                                      return Container(
                                        width: 140.0,
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                        alignment: Alignment.centerLeft,
                                        decoration: BoxDecoration(
                                          border: Border(right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
                                        ),
                                        child: Text(
                                          val,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: context.monoStyle.copyWith(
                                            fontSize: 11.0,
                                            color: bIsSelected ? Colors.amber.shade100 : theme.colorScheme.onSurface,
                                            fontWeight: bIsSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
