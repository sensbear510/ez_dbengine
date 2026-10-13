/* =================================================================================
 * FILE: main_page.dart
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * ---------------------------------------------------------------------------------
 * Master Workplace Page for ezDBUtility with Tab-Scoped Isolated Toolchains.
 * =================================================================================
 */

import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../services/db_service.dart';
import '../../services/ez_dbengine.dart';
import '../../theme/app_theme.dart';
import '../../toolbox/ez_notification.dart';
import '../../toolbox/ez_output.dart';
import '../../toolbox/language.dart';
import '../../toolbox/toolbox.dart';
import '../../toolbox/widgets/about_dialog_panel.dart';
import 'widgets/build_relation_view.dart';
import 'widgets/schema_designer_view.dart';
import '../../toolbox/ebf_tab_context.dart';

/// Tab-Scoped Toolchain Panel Wrapper Widget
class TabToolchainWrapper extends StatefulWidget {
  final EbfTabContext tab;
  final List<EbfTabContext> openedTabs;
  final VoidCallback onLoadEbfRequested;
  final ValueChanged<String> onTableCreated;
  final VoidCallback onCollapse;

  const TabToolchainWrapper({
    super.key,
    required this.tab,
    required this.openedTabs,
    required this.onLoadEbfRequested,
    required this.onTableCreated,
    required this.onCollapse,
  });

  @override
  State<TabToolchainWrapper> createState() => _TabToolchainWrapperState();
}

class _TabToolchainWrapperState extends State<TabToolchainWrapper> {
  final GlobalKey<SchemaDesignerViewState> m_tabSchemaKey = GlobalKey<SchemaDesignerViewState>();

  @override
  Widget build(BuildContext context) {
    final String? strActiveTool = widget.tab.strActiveBottomTool;

    return Stack(
      children: <Widget>[
        // 1. Relation View Studio Panel
        Offstage(
          offstage: strActiveTool != 'relation',
          child: BuildRelationView(
            key: ValueKey('RELATION_STUDIO_${widget.tab.strId}'),
            openedTabs: widget.openedTabs,
            tab: widget.tab,
            onCollapse: () {
              setState(() {
                widget.tab.strActiveBottomTool = null;
              });
              widget.onCollapse();
            },
          ),
        ),

        // 2. Schema Designer Panel
        Offstage(
          offstage: strActiveTool != 'schema',
          child: SchemaDesignerView(
            key: m_tabSchemaKey,
            strEditFilePath: widget.tab.strFilePath.isNotEmpty ? widget.tab.strFilePath : null,
            openedTabs: widget.openedTabs,
            onLoadEbfRequested: widget.onLoadEbfRequested,
            onCollapse: () {
              setState(() {
                widget.tab.strActiveBottomTool = null;
              });
              widget.onCollapse();
            },
            onTableCreated: widget.onTableCreated,
          ),
        ),
      ],
    );
  }
}

/// Master Workplace Page for ezDBUtility with Craftsman Precision Visual Polish
class DesktopMainPage extends StatefulWidget {
  static const String routeName = '/desktop_main';
  final String? strInitialFilePath;

  const DesktopMainPage({
    super.key,
    this.strInitialFilePath,
  });

  @override
  State<DesktopMainPage> createState() => _DesktopMainPageState();
}

class _DesktopMainPageState extends State<DesktopMainPage> {
  final ScrollController m_scrollControllerVerticalFrozen = ScrollController();
  late final AppLifecycleListener m_lifecycleListener;

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

  bool m_bIsDragging = false;

  String m_strActiveEbfPath = '';
  final List<EbfTabContext> m_listTabs = <EbfTabContext>[];
  String? m_strActiveTabId;

  int m_iActiveSlotIndex = 0;
  int m_iSelectedRowIndex = 0;
  int m_iSelectedColIndex = 0;

  final TextEditingController m_controllerSeekInput = TextEditingController();
  final FocusNode m_focusNodeSeekInput = FocusNode();
  final ScrollController m_scrollControllerHorizontalHeader = ScrollController();
  final ScrollController m_scrollControllerHorizontalBody = ScrollController();
  final ScrollController m_scrollControllerVertical = ScrollController();

  final Map<String, TextEditingController> m_mapCellControllers = {};

  EbfTabContext? get m_activeTab {
    if (m_strActiveTabId == null || m_listTabs.isEmpty) return null;
    return m_listTabs.firstWhere(
      (EbfTabContext tab) => tab.strId == m_strActiveTabId,
      orElse: () => m_listTabs.first,
    );
  }

  /// Indicates whether the active mode is EDX Tag index navigation
  bool get m_bIsTagActive => m_strCurrentSearchMode.startsWith('Seek');

  /// Retrieves current active tag_id (1 ~ 8); returns 0 for Locate/Natural mode
  int get m_iCurrentTagId {
    if (!m_bIsTagActive) return 0;
    final int iSlot = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
    return (iSlot >= 0 && iSlot < 8) ? (iSlot + 1) : 0;
  }

  int get m_iActiveTabIndex {
    if (m_strActiveTabId == null) return -1;
    return m_listTabs.indexWhere((tab) => tab.strId == m_strActiveTabId);
  }

  Future<void> _handleOpenEbfDialog() async {
    String? selectedPath;

    if (Platform.isLinux) {
      // 1. Prioritize calling zenity (Ubuntu/GNOME native dialog, instant launch)
      if (_cmdExists('zenity')) {
        try {
          final res = await Process.run('zenity', [
            '--file-selection',
            '--title=Open EBF Database',
            '--file-filter=EBF Database (*.ebf) | *.ebf',
            '--file-filter=All Files (*) | *',
          ]);
          if (res.exitCode == 0) {
            final path = res.stdout.toString().trim();
            if (path.isNotEmpty) selectedPath = path;
          }
        } catch (e) {
          ezOutput('zenity execution failed: $e');
        }
      }

      // 2. Fallback to kdialog (KDE style)
      if (selectedPath == null && _cmdExists('kdialog')) {
        try {
          final res = await Process.run('kdialog', [
            '--getopenfilename',
            Directory.current.path,
            '*.ebf|EBF Database (*.ebf)\n*|All Files (*)',
          ]);
          if (res.exitCode == 0) {
            final path = res.stdout.toString().trim();
            if (path.isNotEmpty) selectedPath = path;
          }
        } catch (e) {
          ezOutput('kdialog execution failed: $e');
        }
      }
    } else {
      // 3. Keep native file_picker on Windows / macOS
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['ebf'],
        );
        selectedPath = result?.files.single.path;
      } catch (e) {
        ezOutput('FilePicker error: $e');
      }
    }

    // 4. Unified loading point regardless of platform selection
    if (selectedPath != null && selectedPath.isNotEmpty) {
      ezOutput('[INFO] Selected Path = $selectedPath');
      await _openEbfFile(selectedPath);
    }
  }

  bool _cmdExists(String cmd) {
    try {
      final res = Process.runSync('which', [cmd]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Opens Schema Designer in "New Mode" (Create Mode) with isolated draft tab
  void _handleOpenNewSchema() {
    // Check if an empty Untitled draft tab already exists to prevent duplicates
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

  /// Converts an active draft tab directly into a physical opened EBF tab upon table creation
  void _convertDraftToOpenedEbf(String strDraftTabId, String strFilePath) {
    final File file = File(strFilePath);
    final String strNormalizedPath = file.absolute.path;
    Directory.current = file.parent.path;
    ezOutput('[INFO] Working directory synchronized to: ${Directory.current.path}');

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
      strActiveBottomTool: null, // Collapse toolchain automatically to show DataGrid
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

    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_EBF_LOADED_TITLE'),
      message: '${m_language.getValue('NOTIF_EBF_LOADED_MSG')} #$iHandle ($strFileName)',
      icon: Icons.check_circle_outline_rounded,
      accentColor: context.craftsmanColors.m_colorInSync,
    );
  }

  void _toggleBottomTool(String? strToolName) {
    if (m_activeTab == null) return;

    setState(() {
      if (m_activeTab!.strActiveBottomTool == strToolName) {
        m_activeTab!.strActiveBottomTool = null;
      } else {
        m_activeTab!.strActiveBottomTool = strToolName;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    windowManager.setTitleBarStyle(TitleBarStyle.normal);
    m_lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleAppExit,
    );

    // Register hardware-level keyboard interceptor
    HardwareKeyboard.instance.addHandler(_handleGlobalHotkeys);

    if (widget.strInitialFilePath != null && widget.strInitialFilePath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEbfFile(widget.strInitialFilePath!);
      });
    }

    if (widget.strInitialFilePath != null && widget.strInitialFilePath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEbfFile(widget.strInitialFilePath!);
      });
    }
    ezOutput('[INFO] MainPage Workstation initialized with Craftsman Precision UI.');
  }

  @override
  void dispose() {
    // Remove hardware-level keyboard interceptor to prevent memory leaks
    HardwareKeyboard.instance.removeHandler(_handleGlobalHotkeys);

    m_lifecycleListener.dispose();
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

  Future<ui.AppExitResponse> _handleAppExit() async {
    ezOutput('[INFO] App exit requested. Gracefully closing all WorkArea handles.');
    _closeAllTabs();
    return ui.AppExitResponse.exit;
  }

  void _clearCellControllers() {
    for (final controller in m_mapCellControllers.values) {
      controller.dispose();
    }
    m_mapCellControllers.clear();
  }

  // =========================================================================
  // Keyboard Interceptor: Hardware-Level Global Hotkeys
  // =========================================================================

  bool _handleGlobalHotkeys(KeyEvent event) {
    // Only process KeyDown events to avoid duplicate triggers
    if (event is! KeyDownEvent) return false;

    // If bottom workbench tool (Relation Studio or Schema Designer) is active,
    // bypass global navigation/grid hotkeys so sub-grids and input fields can handle events natively.
    if (m_activeTab?.strActiveBottomTool != null) {
      return false;
    }

    final bool bIsCtrl = HardwareKeyboard.instance.isControlPressed;
    final bool bIsAlt = HardwareKeyboard.instance.isAltPressed;
    final bool bIsShift = HardwareKeyboard.instance.isShiftPressed;
    final LogicalKeyboardKey key = event.logicalKey;

    // [Home] Jump to First Row
    if (!bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.home) {
      if (m_activeTab != null && m_activeTab!.iHandle != 0) {
        final int iHandle = m_activeTab!.iHandle;
        final int tagId = m_iCurrentTagId;

        // Invoke goTop with current tagId
        m_dbService.goTop(iHandle: iHandle, tagId: tagId);

        setState(() {
          m_iSelectedRowIndex = 0;
          m_iCurrentRecNo = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);
        });

        _ensureCellInView(0, m_iSelectedColIndex);
        _updateStatusBarMetrics();
      }
      return true;
    }

    // [End] Jump to Last Row
    if (!bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.end) {
      if (m_activeTab != null && m_activeTab!.iHandle != 0) {
        final int iHandle = m_activeTab!.iHandle;
        final int tagId = m_iCurrentTagId;
        final int iTotal = m_dbService.getLastRec(iHandle: iHandle, tagId: tagId);

        if (iTotal > 0) {
          // Invoke goBottom with current tagId
          m_dbService.goBottom(iHandle: iHandle, tagId: tagId);

          setState(() {
            m_iSelectedRowIndex = iTotal - 1;
            m_iCurrentRecNo = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);
          });

          _ensureCellInView(iTotal - 1, m_iSelectedColIndex);
          _updateStatusBarMetrics();
        }
      }
      return true;
    }

    // [Ctrl + N] New Schema
    if (bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyN) {
      _handleOpenNewSchema();
      return true;
    }

    // [Ctrl + O] Open EBF
    if (bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyO) {
      _handleOpenEbfDialog();
      return true;
    }

    // [Ctrl + S] Save Current
    if (bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyS) {
      _saveCurrentActiveTab();
      return true;
    }

    // [Ctrl + Alt + S] Save All
    if (bIsCtrl && bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyS) {
      _saveAllTabs();
      return true;
    }

    // [Ctrl + F] Locate Focus
    if (bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyF) {
      _activateLocateMode();
      return true;
    }

    // [Ctrl + G] Go To Row
    if (bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.keyG) {
      _showGoToRowDialog();
      return true;
    }

    // [F3] Seek Next
    if (!bIsCtrl && !bIsAlt && !bIsShift && key == LogicalKeyboardKey.f3) {
      _executeSeek(bSeekNext: true);
      return true;
    }

    // [Shift + F3] Seek Previous
    if (!bIsCtrl && !bIsAlt && bIsShift && key == LogicalKeyboardKey.f3) {
      _executeSeek(bSeekNext: false);
      return true;
    }

    // [Alt + 1 ~ 8] Switch EDX Slot
    if (!bIsCtrl && bIsAlt && !bIsShift) {
      if (key == LogicalKeyboardKey.digit1) {
        _switchEdxSlot(1);
        return true;
      }
      if (key == LogicalKeyboardKey.digit2) {
        _switchEdxSlot(2);
        return true;
      }
      if (key == LogicalKeyboardKey.digit3) {
        _switchEdxSlot(3);
        return true;
      }
      if (key == LogicalKeyboardKey.digit4) {
        _switchEdxSlot(4);
        return true;
      }
      if (key == LogicalKeyboardKey.digit5) {
        _switchEdxSlot(5);
        return true;
      }
      if (key == LogicalKeyboardKey.digit6) {
        _switchEdxSlot(6);
        return true;
      }
      if (key == LogicalKeyboardKey.digit7) {
        _switchEdxSlot(7);
        return true;
      }
      if (key == LogicalKeyboardKey.digit8) {
        _switchEdxSlot(8);
        return true;
      }
    }

    // Return false to let unhandled events bubble down to the Focus Tree (e.g., normal typing)
    return false;
  }

  Future<bool> _openEbfFile(String strFilePath) async {
    try {
      final String strNormalizedPath = File(strFilePath).absolute.path;
      final File file = File(strFilePath);
      Directory.current = file.parent.path;
      ezOutput('[INFO] Working directory synchronized to: ${Directory.current}');

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

        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_TAB_EXISTS_TITLE'),
          message: '[$strFileNameOnly] ${m_language.getValue('NOTIF_TAB_EXISTS_MSG')}',
          icon: Icons.tab_rounded,
          accentColor: Colors.amber.shade800,
        );
        return true;
      }

      final int iHandle = m_dbService.use(strNormalizedPath, nullptr);
      if (iHandle == 0) {
        final String strMsg = m_language.getValue('NOTIF_MSG_OPEN_FAIL').replaceAll('{filename}', strFileNameOnly);

        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_TITLE_OPEN_FAIL'),
          message: strMsg,
          icon: Icons.error_outline_rounded,
          accentColor: Colors.red,
        );
        return false;
      }

      final List<EzTag> lstTags = m_dbService.getTags(iHandle: iHandle);
      final List<String> lstEdxKeys = lstTags.map((EzTag t) => '${t.name} (${t.expression})').toList();

      setState(() {
        m_strActiveEbfPath = strNormalizedPath;

        final EbfTabContext newTab = EbfTabContext(
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

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('NOTIF_EBF_LOADED_TITLE'),
        message: '${m_language.getValue('NOTIF_EBF_LOADED_MSG')} #$iHandle ($strFileNameOnly)',
        icon: Icons.check_circle_outline_rounded,
        accentColor: context.craftsmanColors.m_colorInSync,
      );
      return true;
    } catch (e) {
      ezOutput('[EXCEPTION] Error opening EBF file via use(): $e');
      return false;
    }
  }

  void _closeTab(String strTabId) {
    setState(() {
      final int iIndex = m_listTabs.indexWhere((EbfTabContext tab) => tab.strId == strTabId);
      if (iIndex != -1) {
        final EbfTabContext removedTab = m_listTabs.removeAt(iIndex);

        if (removedTab.iHandle != 0) {
          try {
            m_dbService.close(iHandle: removedTab.iHandle);
          } catch (e) {
            ezOutput('[ERROR] Exception while executing close: $e');
          }
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

  void _saveCurrentActiveTab() {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    _commitRowChanges(m_iSelectedRowIndex);
    m_dbService.commit(iHandle: m_activeTab!.iHandle);

    setState(() {
      m_bIsDirty = false;
    });

    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_SAVE_SUCCESS_TITLE'),
      message: '${m_language.getValue('NOTIF_SAVE_SUCCESS_MSG')} ${m_activeTab!.strFileName}',
      icon: Icons.save_rounded,
    );
  }

  void _saveAllTabs() {
    if (m_listTabs.isEmpty) return;

    _commitRowChanges(m_iSelectedRowIndex);
    for (final tab in m_listTabs) {
      if (tab.iHandle != 0) {
        m_dbService.commit(iHandle: tab.iHandle);
      }
    }

    setState(() {
      m_bIsDirty = false;
    });

    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_SAVE_ALL_SUCCESS_TITLE'),
      message: m_language.getValue('NOTIF_SAVE_ALL_SUCCESS_MSG'),
      icon: Icons.done_all_rounded,
    );
  }

  void _saveRelation() {
    _toggleBottomTool('relation');
  }

  void _loadRelation() {
    _toggleBottomTool('relation');
    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_LOAD_ERL_TITLE'),
      message: m_language.getValue('REL_PREVIEW_HINT'),
      icon: Icons.folder_open_rounded,
    );
  }

  void _packActiveDatabase() {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    _clearDataBuffer();
    _clearCellControllers();

    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_PACK_TITLE'),
      message: '${m_language.getValue('NOTIF_PACK_MSG')} #${m_activeTab!.iHandle}...',
      icon: Icons.cleaning_services_rounded,
    );
  }

  void _closeAllTabs() {
    for (final EbfTabContext tab in List<EbfTabContext>.from(m_listTabs)) {
      _closeTab(tab.strId);
    }
  }

  void _switchEdxSlot(int iSlotNum) {
    if (iSlotNum < 1 || iSlotNum > 8) return;
    final int iSlotIndex = iSlotNum - 1;

    setState(() {
      final int iCurrentActive = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
      final bool bIsCurrentlyActive = (iCurrentActive == iSlotIndex) && m_strCurrentSearchMode.startsWith('Seek');

      if (bIsCurrentlyActive) {
        // Clicking an already selected tag reverts to Locate (Natural EBF physical order)
        m_strCurrentSearchMode = 'Locate';
        if (m_activeTab != null) {
          m_activeTab!.iActiveSlotIndex = -1;
        }
      } else {
        // Activate specified EDX Tag
        if (m_activeTab != null) {
          m_activeTab!.iActiveSlotIndex = iSlotIndex;
        }
        m_iActiveSlotIndex = iSlotIndex;
        m_strCurrentSearchMode = 'Seek [$iSlotNum]';
      }

      // Clear cache, reset row number and scrollbars to trigger 200-row reload under new EDX order
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

    // Synchronize C engine cursor to top (gotop includes current tagId)
    if (m_activeTab != null && m_activeTab!.iHandle != 0) {
      m_dbService.goTop(
        iHandle: m_activeTab!.iHandle,
        tagId: m_iCurrentTagId,
      );
    }
    _updateStatusBarMetrics();
  }

  void _activateLocateMode() {
    setState(() {
      m_strCurrentSearchMode = 'Locate';
    });
    m_focusNodeSeekInput.requestFocus();
  }

  void _jumpToRowId(int iRowId) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iTotalRecords = m_dbService.getRecordCount(iHandle: m_activeTab!.iHandle);
    if (iRowId < 1 || iRowId > iTotalRecords) return;

    setState(() {
      m_iSelectedRowIndex = iRowId - 1;
      m_iCurrentRecNo = iRowId;
      // Ensure column index doesn't go out of bounds or trigger strange horizontal shifts after jump
      if (m_iSelectedColIndex < 0) {
        m_iSelectedColIndex = 0;
      }
    });
    m_dbService.goTo(m_iCurrentRecNo, iHandle: m_activeTab!.iHandle);
    _ensureCellInView(m_iSelectedRowIndex, m_iSelectedColIndex);
    _updateStatusBarMetrics();
  }

  void _showGoToRowDialog() {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iTotalRecords = m_dbService.getRecordCount(iHandle: m_activeTab!.iHandle);
    if (iTotalRecords <= 0) return;

    final TextEditingController controllerRowId = TextEditingController(
      text: '${m_iSelectedRowIndex + 1}',
    );

    showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'GoToRowDialog',
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, anim1, anim2, child) {
        final CurvedAnimation curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.0),
            end: Offset.zero,
          ).animate(curved),
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 40.0),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 340.0,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8.0),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 16.0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(
                              m_language.getValue('MENU_GO_TO'),
                              style: context.uiBoldStyle.copyWith(fontSize: 13.0),
                            ),
                            Text(
                              '(1 - $iTotalRecords)',
                              style: context.monoCaptionStyle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12.0),
                        TextField(
                          controller: controllerRowId,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                          style: context.monoStyle,
                          decoration: InputDecoration(
                            labelText: m_language.getValue('LABEL_ROW_ID'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (String strVal) {
                            final int? iTarget = int.tryParse(strVal);
                            if (iTarget != null && iTarget >= 1 && iTarget <= iTotalRecords) {
                              Navigator.of(context).pop(iTarget);
                            }
                          },
                        ),
                        const SizedBox(height: 12.0),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(m_language.getValue('BTN_CANCEL'), style: context.uiStyle),
                            ),
                            const SizedBox(width: 8.0),
                            ElevatedButton(
                              onPressed: () {
                                final int? iTarget = int.tryParse(controllerRowId.text);
                                if (iTarget != null && iTarget >= 1 && iTarget <= iTotalRecords) {
                                  Navigator.of(context).pop(iTarget);
                                }
                              },
                              child: Text('OK', style: context.uiBoldStyle),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ).then((int? iResultRowId) {
      if (iResultRowId != null) {
        _jumpToRowId(iResultRowId);
      }
    });
  }

  void _executeSeek({bool bSeekNext = true}) {
    final String strSeekKey = m_controllerSeekInput.text.trim();
    if (strSeekKey.isEmpty) return;

    final int? iHandle = m_activeTab?.iHandle;
    if (iHandle == null || iHandle == 0) return;

    // Double protection: Ensure underlying C engine working directory matches current tab before I/O search
    if (m_activeTab?.strFilePath != null && m_activeTab!.strFilePath.isNotEmpty) {
      Directory.current = File(m_activeTab!.strFilePath).parent.path;
    }

    if (m_strCurrentSearchMode == 'Locate') {
      final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
      if (lstFdt.isEmpty) return;

      final int iColIdx = (m_iSelectedColIndex >= 0 && m_iSelectedColIndex < lstFdt.length) ? m_iSelectedColIndex : 0;
      final String strTargetField = lstFdt[iColIdx].name;

      // Synchronous physical cursor
      // Because DataGrid readRecordVector moves C engine cursor to buffer end (e.g. 200th record),
      // pull cursor back to current UI selection (m_iCurrentRecNo) before Locate.
      int iTargetSyncRec = m_iCurrentRecNo > 0 ? m_iCurrentRecNo : 1;

      // Advance cursor by one for seek-next to prevent finding the identical record repeatedly
      if (bSeekNext && m_iCurrentRecNo > 0) {
        iTargetSyncRec++;
      }
      m_dbService.goTo(iTargetSyncRec, iHandle: iHandle);

      final int iLocateStatus = m_dbService.locate(
        strTargetField,
        strSeekKey,
        bPartialMatch: false,
        iHandle: iHandle,
      );

      if (iLocateStatus == 0) {
        final int iFoundRecNo = m_dbService.getRecNo(iHandle: iHandle);
        if (iFoundRecNo > 0) {
          m_focusNodeSeekInput.unfocus();
          _jumpToRowId(iFoundRecNo);
        }
      } else {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_SEARCH_NOT_FOUND_TITLE'),
          message:
              '${m_language.getValue('NOTIF_SEARCH_NOT_FOUND_MSG')} [$strSeekKey] (${m_language.getValue('GRID_COL')}: $strTargetField)',
          icon: Icons.search_off_rounded,
          accentColor: Colors.orange,
        );
      }
    } else {
      final List<EzTag> lstTags = m_dbService.getTags(iHandle: iHandle);
      final int iSlotIndex = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;

      if (iSlotIndex < 0 || iSlotIndex >= lstTags.length) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_INVALID_TAG_TITLE'),
          message: m_language.getValue('NOTIF_INVALID_TAG_MSG'),
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.redAccent,
        );
        return;
      }

      final String strTagName = lstTags[iSlotIndex].name;
      final bool bFound = m_dbService.seekByName(strTagName, <String>[strSeekKey], iHandle: iHandle);

      if (bFound) {
        final int iFoundNodeIndex = m_dbService.getRecNo(iHandle: iHandle, tagId: m_iCurrentTagId);
        if (iFoundNodeIndex > 0) {
          m_focusNodeSeekInput.unfocus();
          _jumpToRowId(iFoundNodeIndex);
        }
      } else {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('NOTIF_SEARCH_NOT_FOUND_TITLE'),
          message: '${m_language.getValue('NOTIF_SEARCH_NOT_FOUND_MSG')} [$strSeekKey] (Tag: $strTagName)',
          icon: Icons.search_off_rounded,
          accentColor: Colors.orange,
        );
      }
    }
    _updateStatusBarMetrics();
  }

  void _navigateRowSelection({required bool bMoveDown}) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iHandle = m_activeTab!.iHandle;
    final int tagId = m_iCurrentTagId;

    // 1. Retrieve total record count for current track (total_recs for Natural, node_count for Tag)
    final int iTotal = m_dbService.getLastRec(iHandle: iHandle, tagId: tagId);
    if (iTotal <= 0) return;

    if (bMoveDown) {
      // ==========================================
      // Down arrow navigation
      // ==========================================
      if (m_iSelectedRowIndex < iTotal - 1) {
        // Move down: Increment selected row
        m_iSelectedRowIndex++;
        m_bIsBof = false;
        m_bIsEof = false;
        // Reposition C engine to new 1-based row, overriding any cursor drift from background caching
        m_dbService.goTo(m_iSelectedRowIndex + 1, iHandle: iHandle, tagId: tagId);
      } else {
        // Boundary check: Pressing down on the last row triggers EOF
        m_dbService.goTo(iTotal, iHandle: iHandle, tagId: tagId);
        m_dbService.skip(1, iHandle: iHandle, tagId: tagId);
        m_bIsEof = m_dbService.isEof(iHandle: iHandle, tagId: tagId);
        m_bIsBof = false;
      }
    } else {
      // ==========================================
      // Up arrow navigation
      // ==========================================
      if (m_iSelectedRowIndex > 0) {
        // Move up: Decrement selected row
        m_iSelectedRowIndex--;
        m_bIsBof = false;
        m_bIsEof = false;
        // Reposition C engine to new 1-based row for consistent upward navigation
        m_dbService.goTo(m_iSelectedRowIndex + 1, iHandle: iHandle, tagId: tagId);
      } else {
        // Boundary check: Pressing up on row 0 triggers BOF
        m_dbService.goTo(1, iHandle: iHandle, tagId: tagId);
        m_dbService.skip(-1, iHandle: iHandle, tagId: tagId);
        m_bIsBof = m_dbService.isBof(iHandle: iHandle, tagId: tagId);
        m_bIsEof = false;
      }
    }

    // Retrieve corresponding physical EBF record number
    setState(() {
      m_iCurrentRecNo = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);
    });

    _ensureCellInView(m_iSelectedRowIndex, m_iSelectedColIndex);
  }

  /// Synchronizes the C-engine physical record pointer and updates status bar metrics
  /// whenever a row or cell is clicked by the mouse.
  void _selectRowAndSyncEngine(int iRowIndex, {int? iColIndex}) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;

    final int iTargetRecNo = iRowIndex + 1;

    setState(() {
      m_iSelectedRowIndex = iRowIndex;
      if (iColIndex != null) m_iSelectedColIndex = iColIndex;
      m_iCurrentRecNo = iTargetRecNo;
      m_iEditingRowIndex = null;
    });

    // Synchronize cursor for currently active Tag
    m_dbService.goTo(
      iTargetRecNo,
      iHandle: m_activeTab!.iHandle,
      tagId: m_iCurrentTagId,
    );

    _updateStatusBarMetrics();
  }

  void _navigateColSelection({required bool bMoveRight}) {
    final int? iHandle = m_activeTab?.iHandle;
    if (iHandle == null || iHandle == 0) return;
    final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
    if (lstFdt.isEmpty) return;

    setState(() {
      if (bMoveRight) {
        if (m_iSelectedColIndex < lstFdt.length - 1) {
          m_iSelectedColIndex++;
        }
      } else {
        if (m_iSelectedColIndex > 0) {
          m_iSelectedColIndex--;
        }
      }
    });

    _ensureCellInView(m_iSelectedRowIndex, m_iSelectedColIndex);
  }

  void _copySelectedRowToClipboard() {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;

    final int iRecNo = m_iSelectedRowIndex + 1;
    final int iHandle = m_activeTab!.iHandle;

    m_dbService.goTo(iRecNo, iHandle: iHandle);
    final EzRecordReader? reader = m_dbService.readRecord();
    final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);

    if (reader == null) return;

    final List<String> lstValues = <String>[];
    for (final EzField field in lstFdt) {
      lstValues.add(reader.stringAt(field.offset, field.len));
    }

    final String strTsvRecord = lstValues.join('\t');
    Clipboard.setData(ClipboardData(text: strTsvRecord));

    EzNotification.showTopPanel(
      context,
      title: m_language.getValue('NOTIF_CLIPBOARD_TITLE'),
      message: '${m_language.getValue('NOTIF_CLIPBOARD_MSG')} #$iRecNo',
      icon: Icons.content_copy_rounded,
    );
  }

  void _toggleDeleteSelectedRow(int iRowIndex) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int iRecNo = iRowIndex + 1;
    final int iHandle = m_activeTab!.iHandle;
    m_dbService.goTo(iRecNo, iHandle: iHandle);
    // 2. Query soft-deletion status of current record
    final bool bIsDeleted = m_dbService.isDeleted(iRecNo, iHandle);

    // 3. Dispatch delete or recall based on active status
    if (bIsDeleted) {
      m_dbService.recallRecord(iHandle: iHandle);
    } else {
      m_dbService.deleteRecord(iHandle: iHandle);
    }
    _clearDataBuffer();
    _updateStatusBarMetrics();

    setState(() {
      m_bIsDirty = true;
    });
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

    // Direct state updates without redundant local variables
    setState(() {
      m_iTotalRecs = m_dbService.getLastRec(iHandle: iHandle, tagId: tagId);
      m_iCurrentRecNo = (m_iTotalRecs > 0) ? (m_iSelectedRowIndex + 1) : 0;
      m_iDeletedCount = m_dbService.getDeleteCount(iHandle: iHandle);
      m_bIsBof = m_dbService.isBof(iHandle: iHandle, tagId: tagId);
      m_bIsEof = m_dbService.isEof(iHandle: iHandle, tagId: tagId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;
    final double dScreenWidth = MediaQuery.of(context).size.width;
    final bool bUseDesktopMode = kIsWeb || dScreenWidth >= 600.0;

    final Map<ShortcutActivator, VoidCallback> mapHotkeys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.f4, alt: true): () {
        _closeAllTabs();
        exit(0);
      },
      const SingleActivator(LogicalKeyboardKey.f4, control: true): () {
        if (m_strActiveTabId != null) _closeTab(m_strActiveTabId!);
      },
      // Restore directional navigation hotkeys to CallbackShortcuts where they worked flawlessly
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _navigateRowSelection(bMoveDown: true),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _navigateRowSelection(bMoveDown: false),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _navigateColSelection(bMoveRight: true),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _navigateColSelection(bMoveRight: false),

      const SingleActivator(LogicalKeyboardKey.keyC, control: true): _copySelectedRowToClipboard,
      const SingleActivator(LogicalKeyboardKey.delete): () => _toggleDeleteSelectedRow(m_iSelectedRowIndex),
      const SingleActivator(LogicalKeyboardKey.tab, control: true): _switchToNextTab,
      const SingleActivator(LogicalKeyboardKey.tab, control: true, shift: true): _switchToPreviousTab,
      const SingleActivator(LogicalKeyboardKey.pageDown, control: true): _switchToNextTab,
      const SingleActivator(LogicalKeyboardKey.pageUp, control: true): _switchToPreviousTab,
    };

    final bool bHasActiveTool = m_activeTab?.strActiveBottomTool != null;

    return CallbackShortcuts(
      bindings: mapHotkeys,
      child: Focus(
        autofocus: true,
        child: Title(
          title: m_language.getValue('TITLE'),
          color: theme.primaryColor,
          child: DropTarget(
            onDragEntered: (_) => setState(() => m_bIsDragging = true),
            onDragExited: (_) => setState(() => m_bIsDragging = false),
            onDragDone: (detail) {
              setState(() => m_bIsDragging = false);
              for (final file in detail.files) {
                if (file.path.toLowerCase().endsWith('.ebf')) {
                  _openEbfFile(file.path);
                  break;
                }
              }
            },
            child: Stack(
              children: <Widget>[
                Scaffold(
                  key: const Key('ez_db_main_scaffold'),
                  backgroundColor: theme.scaffoldBackgroundColor,
                  resizeToAvoidBottomInset: false,
                  body: SafeArea(
                    child: Column(
                      children: <Widget>[
                        _buildTopMenuBar(context, theme, craftsmanColors),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              _buildWorkAreaTabBar(context, theme, craftsmanColors),
                              Expanded(
                                child: Column(
                                  key: ValueKey('DATAGRID_WORKPLACE_${m_strActiveTabId ?? "EMPTY"}'),
                                  children: <Widget>[
                                    _buildHeaderShell(context, theme, craftsmanColors),
                                    Divider(
                                        height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                                    _buildSmartSeekBar(context, theme, craftsmanColors),
                                    Divider(
                                        height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                                    Expanded(
                                      child: _buildDataGridWorkplace(context, theme, craftsmanColors, bUseDesktopMode),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  bottomNavigationBar: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      // Hide TOOLBOX completely when no EBF tabs exist
                      if (m_listTabs.isNotEmpty) ...<Widget>[
                        _buildBottomToolNavigationBar(context, theme, craftsmanColors),
                        Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                      ],
                      bUseDesktopMode
                          ? _buildStatusBar(
                              activeTab: m_activeTab,
                              strSearchMode: m_strCurrentSearchMode,
                              iCurrentRecNo: m_iCurrentRecNo,
                              iTotalRecs: m_iTotalRecs,
                              iDeletedCount: m_iDeletedCount,
                              bIsDirty: m_bIsDirty,
                              theme: theme,
                            )
                          : _buildMobileBottomDock(context, theme, craftsmanColors),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  // Top offset keeps room for MenuBar(36) + TabBar(32) + HeaderShell(88) = total 156.0px
                  top: bHasActiveTool ? 156.0 : MediaQuery.of(context).size.height,
                  bottom: bHasActiveTool ? 24.0 : -MediaQuery.of(context).size.height,
                  left: 0.0,
                  right: 0.0,
                  child: Material(
                    elevation: 16.0,
                    color: theme.cardColor,
                    child: Visibility(
                      visible: bHasActiveTool,
                      maintainState: true,
                      child: SizedBox(
                        height: 380.0,
                        child: _buildActiveBottomToolView(),
                      ),
                    ),
                  ),
                ),
                if (m_bIsDragging)
                  Positioned.fill(
                    child: Container(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 18.0),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
                              width: 2.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.file_download_outlined,
                                  size: 28.0, color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary),
                              const SizedBox(width: 12.0),
                              Text(
                                m_language.getValue('DROP_EBF_HINT'),
                                style: context.uiBoldStyle.copyWith(fontSize: 14.0),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // MenuBar Builder: Dynamic Navigation Header
  // =========================================================================

  Widget _buildTopMenuBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    return Container(
      height: 36.0,
      color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
      child: Row(
        children: <Widget>[
          Expanded(
            child: MenuBar(
              style: MenuStyle(
                backgroundColor: WidgetStateProperty.all(craftsmanColors.m_colorHeaderBg ?? theme.cardColor),
                elevation: WidgetStateProperty.all(0),
              ),
              children: <Widget>[
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyN, control: true),
                      onPressed: _handleOpenNewSchema,
                      child: Text(m_language.getValue('MENU_NEW_TABLE'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyO, control: true),
                      onPressed: _handleOpenEbfDialog,
                      child: Text(m_language.getValue('MENU_OPEN_EXPLORER'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
                      onPressed: _saveCurrentActiveTab,
                      child: Text(m_language.getValue('MENU_SAVE'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true),
                      onPressed: () {},
                      child: Text(m_language.getValue('MENU_SAVE_AS'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true, alt: true),
                      onPressed: _saveAllTabs,
                      child: Text(m_language.getValue('MENU_SAVE_ALL'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.f4, control: true),
                      onPressed: () {
                        if (m_strActiveTabId != null) _closeTab(m_strActiveTabId!);
                      },
                      child: Text(m_language.getValue('MENU_CLOSE_TAB'), style: context.uiStyle),
                    ),
                    const Divider(),
                    MenuItemButton(
                      onPressed: _saveRelation,
                      child: Text(m_language.getValue('MENU_SAVE_RELATION'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      onPressed: _loadRelation,
                      child: Text(m_language.getValue('MENU_LOAD_RELATION'), style: context.uiStyle),
                    ),
                    const Divider(),
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_LOAD'), style: context.uiStyle)),
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_EXPORT'), style: context.uiStyle)),
                    const Divider(),
                    MenuItemButton(
                      onPressed: () {
                        _closeAllTabs();
                        exit(0);
                      },
                      child: Text(m_language.getValue('MENU_EXIT'), style: context.uiStyle),
                    ),
                  ],
                  child: Text(m_language.getValue('MENU_FILE'), style: context.uiStyle),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyF, control: true),
                      onPressed: _activateLocateMode,
                      child: Text(m_language.getValue('MENU_FIND_KEYWORD'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.keyG, control: true),
                      onPressed: () {},
                      child: Text(m_language.getValue('MENU_GO_TO'), style: context.uiStyle),
                    ),
                    SubmenuButton(
                      menuChildren: List.generate(8, (i) {
                        final slot = i + 1;
                        return MenuItemButton(
                          onPressed: () => _switchEdxSlot(slot),
                          child: Text('Slot [$slot] (Alt+$slot)', style: context.uiStyle),
                        );
                      }),
                      child: Text(m_language.getValue('MENU_USE_INDEX'), style: context.uiStyle),
                    ),
                    MenuItemButton(
                      shortcut: const SingleActivator(LogicalKeyboardKey.delete),
                      onPressed: () => _toggleDeleteSelectedRow(m_iSelectedRowIndex),
                      child: Text(m_language.getValue('MENU_DELETE_TOGGLE'), style: context.uiStyle),
                    ),
                  ],
                  child: Text(m_language.getValue('MENU_EDIT'), style: context.uiStyle),
                ),
                SubmenuButton(
                  menuChildren: <Widget>[
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_CLEAR_DATA'), style: context.uiStyle)),
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_BACKUP'), style: context.uiStyle)),
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_RESTORE'), style: context.uiStyle)),
                    MenuItemButton(
                        onPressed: _packActiveDatabase, child: Text(m_language.getValue('MENU_PACK_DB'), style: context.uiStyle)),
                    const Divider(),
                    MenuItemButton(onPressed: () {}, child: Text(m_language.getValue('MENU_PLUGIN'), style: context.uiStyle)),
                    const Divider(),
                    MenuItemButton(
                      onPressed: () => AboutDialogPanel.show(context),
                      child: Text(m_language.getValue('MENU_ABOUT'), style: context.uiStyle),
                    ),
                  ],
                  child: Text(m_language.getValue('MENU_TOOLS'), style: context.uiStyle),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Status Bar: Classic DBU Status Bar Component
  // =========================================================================

  Widget _buildStatusBar({
    required EbfTabContext? activeTab,
    required String strSearchMode,
    required int iCurrentRecNo,
    required int iTotalRecs,
    required int iDeletedCount,
    required bool bIsDirty,
    required ThemeData theme,
  }) {
    if (activeTab == null) {
      return Container(
        height: 24.0,
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        alignment: Alignment.centerLeft,
        child: Text(m_language.getValue('STATUS_READY'), style: context.monoStyle),
      );
    }

    return Container(
      height: 24.0,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        children: <Widget>[
          _buildStatusItem(Icons.insert_drive_file_outlined, activeTab.strFileName),
          _buildDivider(),
          _buildStatusItem(Icons.format_list_numbered, 'REC: $iCurrentRecNo / $iTotalRecs'),
          _buildDivider(),
          // BOF / EOF Status Indicator Badges
          _buildStatusItem(
            Icons.vertical_align_top,
            'BOF',
            color: m_bIsBof ? Colors.amber.shade800 : Colors.grey.shade500,
            isBold: m_bIsBof,
          ),
          const SizedBox(width: 4.0),
          _buildStatusItem(
            Icons.vertical_align_bottom,
            'EOF',
            color: m_bIsEof ? Colors.red.shade700 : Colors.grey.shade500,
            isBold: m_bIsEof,
          ),
          _buildDivider(),
          _buildStatusItem(
            Icons.search,
            'MODE: $strSearchMode',
            color: strSearchMode.startsWith('Seek') ? Colors.amber.shade900 : Colors.green.shade800,
            isBold: true,
          ),
          _buildDivider(),
          _buildStatusItem(Icons.delete_outline, 'DEL: $iDeletedCount'),
          const Spacer(),
          if (bIsDirty) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
              decoration: BoxDecoration(color: Colors.amber.shade700, borderRadius: BorderRadius.circular(2.0)),
              child: Text(m_language.getValue('STATUS_MODIFIED'),
                  style: context.uiBoldStyle.copyWith(color: Colors.white, fontSize: 10.0)),
            ),
            const SizedBox(width: 8.0),
          ],
          Text('R/W', style: context.monoBoldStyle),
        ],
      ),
    );
  }

  Widget _buildStatusItem(IconData icon, String text, {Color? color, bool isBold = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.0, color: color ?? Colors.grey.shade700),
        const SizedBox(width: 4.0),
        Text(
          text,
          style: isBold ? context.monoBoldStyle.copyWith(color: color) : context.monoStyle.copyWith(color: color),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return VerticalDivider(width: 16.0, indent: 4.0, endIndent: 4.0, color: Colors.grey.shade400);
  }

  // =========================================================================
  // Tab Bar: Multi-Tab Ribbon Component
  // =========================================================================

  Widget _buildWorkAreaTabBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    return Container(
      height: 32.0,
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: <Widget>[
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: m_listTabs.length,
              itemBuilder: (BuildContext context, int iIndex) {
                final EbfTabContext tab = m_listTabs[iIndex];
                final bool bIsSelected = tab.strId == m_strActiveTabId;

                return InkWell(
                  onTap: () {
                    setState(() {
                      m_strActiveTabId = tab.strId;
                      m_strActiveEbfPath = tab.strFilePath;
                      // When switching tabs, force C engine working directory back to target file directory
                      // to ensure EDX index tree correctly resolves underlying entity files.
                      if (tab.strFilePath.isNotEmpty) {
                        try {
                          Directory.current = File(tab.strFilePath).parent.path;
                          ezOutput('[INFO] Switched Context CWD to: ${Directory.current.path}');
                        } catch (e) {
                          ezOutput('[ERROR] Failed to switch CWD: $e');
                        }
                      }
                      _updateStatusBarMetrics();
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    decoration: BoxDecoration(
                      color: bIsSelected ? (craftsmanColors.m_colorCardBg ?? theme.cardColor) : theme.scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(color: bIsSelected ? theme.colorScheme.primary : Colors.transparent, width: 2.0),
                        right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 1.0),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.table_chart_outlined,
                            size: 14.0,
                            color: bIsSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 6.0),
                        Text(
                          tab.strFileName,
                          style: bIsSelected
                              ? context.uiBoldStyle.copyWith(fontSize: 11.0)
                              : context.uiStyle.copyWith(fontSize: 11.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                        const SizedBox(width: 8.0),
                        GestureDetector(
                          onTap: () => _closeTab(tab.strId),
                          child: Icon(Icons.close_rounded, size: 12.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                        ),
                      ],
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

  // =========================================================================
  // Header Shell: Anchor & EDX 8-Slot Focus Carousel Ribbon
  // =========================================================================

  Widget _buildHeaderShell(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final List<String> lstEdxKeys = m_activeTab?.listEdxKeys ?? <String>[];

    return Container(
      height: 88.0,
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
      color: craftsmanColors.m_colorCardBg ?? theme.cardColor,
      child: Row(
        children: <Widget>[
          _buildEbfAnchorCard(context, theme, craftsmanColors),
          VerticalDivider(width: 16.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
          Expanded(
            child: lstEdxKeys.isEmpty
                ? Center(
                    child: Text(
                      m_language.getValue('NO_EDX_INDEX'),
                      style: context.monoCaptionStyle,
                    ),
                  )
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: List<Widget>.generate(lstEdxKeys.length, (int iIndex) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: SizedBox(
                            width: 135.0,
                            child: _buildEdxSlotCard(context, iIndex, lstEdxKeys[iIndex], theme, craftsmanColors),
                          ),
                        );
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEbfAnchorCard(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final String strFileName = m_activeTab?.strFileName ??
        (m_strActiveEbfPath.isNotEmpty ? m_strActiveEbfPath.split(RegExp(r'[/\\]')).last : m_language.getValue('NO_TABLE_LOADED'));

    return Container(
      width: 150.0,
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 1.0),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_open_rounded, color: theme.colorScheme.primary, size: 20.0),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(m_language.getValue('EBF_ANCHOR'),
                    style: context.uiBoldStyle.copyWith(fontSize: 10.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                Text(strFileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: context.uiBoldStyle.copyWith(fontSize: 11.0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEdxSlotCard(BuildContext context, int iIndex, String strKeyExpr, ThemeData theme, CraftsmanColors craftsmanColors) {
    final int iCurrentActive = m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex;
    final bool bIsActiveSlot = (iIndex == iCurrentActive) && m_strCurrentSearchMode.startsWith('Seek');
    final bool bHasYellowFocus = bIsActiveSlot;

    return InkWell(
      onTap: () => _switchEdxSlot(iIndex + 1),
      borderRadius: BorderRadius.circular(6.0),
      child: Container(
        padding: const EdgeInsets.all(8.0),
        decoration: BoxDecoration(
          color: bHasYellowFocus
              ? Colors.amber.withValues(alpha: 0.15)
              : (craftsmanColors.m_colorCardBg ?? theme.scaffoldBackgroundColor),
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(
            color: bHasYellowFocus ? Colors.amber.shade700 : (craftsmanColors.m_colorBorder ?? theme.dividerColor),
            width: bHasYellowFocus ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Alt+${iIndex + 1}',
                  style: context.uiBoldStyle.copyWith(
                      fontSize: 11.0,
                      color: bHasYellowFocus ? Colors.amber.shade900 : theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                ),
                Icon(Icons.vpn_key_rounded,
                    size: 12.0,
                    color: bHasYellowFocus ? Colors.amber.shade900 : theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              strKeyExpr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.monoCaptionStyle,
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Search Bar: Smart Seek / Locate Bar Component
  // =========================================================================

  Widget _buildSmartSeekBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final bool bHasActiveTab = m_activeTab != null && m_activeTab!.iHandle != 0;
    final int iActiveSlot = (m_activeTab?.iActiveSlotIndex ?? m_iActiveSlotIndex) + 1;
    final bool bIsLocate = m_strCurrentSearchMode == 'Locate';

    return Container(
      key: const Key('ez_db_smart_seek_bar'),
      height: 48.0,
      color: theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.search,
              size: 18.0, color: bIsLocate ? Colors.green : (craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary)),
          const SizedBox(width: 8.0),
          Text(
            bIsLocate ? 'Locate:' : '${m_language.getValue('SEEK_SLOT_LABEL')} [$iActiveSlot]:',
            style: context.uiBoldStyle.copyWith(
                fontSize: 12.0,
                color: bIsLocate ? Colors.green.shade800 : (craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary)),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: TextField(
              key: const Key('ez_db_seek_input_field'),
              controller: m_controllerSeekInput,
              focusNode: m_focusNodeSeekInput,
              enabled: bHasActiveTab,
              style: context.uiStyle,
              onSubmitted: (_) => _executeSeek(),
              decoration: InputDecoration(
                hintText: m_language.getValue('SEEK_HINT_INPUT'),
                hintStyle: context.uiStyle.copyWith(fontSize: 11.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                filled: true,
                fillColor: theme.scaffoldBackgroundColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4.0), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 10.0),
          ElevatedButton.icon(
            key: const Key('ez_db_seek_action_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  bIsLocate ? Colors.green.shade700 : (craftsmanColors.m_colorCraftsmanBrown ?? theme.colorScheme.primary),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
            ),
            onPressed: bHasActiveTab ? () => _executeSeek() : null,
            icon: const Icon(Icons.arrow_forward, size: 14.0),
            label: Text(
              bIsLocate ? 'Locate (F3)' : m_language.getValue('BTN_SEEK_F3'),
              style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Workplace Grid: Dynamic DataGrid Workplace Architecture
  // =========================================================================

  Widget _buildDataGridWorkplace(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors, bool bUseDesktopMode) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.subtitles_off, size: 48.0, color: theme.dividerColor),
            const SizedBox(height: 12.0),
            Text(m_language.getValue('NO_DATASET_LOADED'),
                style: context.uiStyle.copyWith(fontSize: 14.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    final int iHandle = m_activeTab!.iHandle;
    final List<EzField> lstFdt = m_dbService.getFdt(iHandle: iHandle);
    final List<String> lstHeaders = lstFdt.map((EzField f) => f.name).toList();
    final int iTotalRecords = m_dbService.getRecordCount(iHandle: iHandle);

    final double dScrollableWidth = lstHeaders.length * 150.0;
    final double dFrozenWidth = bUseDesktopMode ? 160.0 : 72.0;

    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: m_notifierBufferUpdate,
        builder: (BuildContext context, int iUpdateSignal, Widget? child) {
          return Stack(
            children: <Widget>[
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
                  child: Scrollbar(
                    controller: m_scrollControllerHorizontalBody,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10.0,
                    child: SingleChildScrollView(
                      controller: m_scrollControllerHorizontalBody,
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        padding: EdgeInsets.only(left: dFrozenWidth),
                        width: dScrollableWidth + dFrozenWidth,
                        child: Column(
                          children: <Widget>[
                            _buildDataColumnsHeader(lstHeaders, dScrollableWidth, theme, craftsmanColors),
                            Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                            Expanded(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (ScrollNotification notif) {
                                  if (notif is ScrollUpdateNotification && m_scrollControllerVerticalFrozen.hasClients) {
                                    m_scrollControllerVerticalFrozen.jumpTo(m_scrollControllerVertical.offset);
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: m_scrollControllerVertical,
                                  itemExtent: 36.0,
                                  // ignore: deprecated_member_use
                                  cacheExtent: 600.0,
                                  itemCount: iTotalRecords,
                                  itemBuilder: (BuildContext context, int iRowIndex) {
                                    return _buildRowDataCellsOnly(
                                        context, iRowIndex, lstHeaders, dScrollableWidth, theme, craftsmanColors);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0.0,
                top: 0.0,
                bottom: 10.0,
                width: dFrozenWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    border: Border(right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 1.5)),
                  ),
                  child: Column(
                    children: <Widget>[
                      _buildFrozenHeaderPane(theme, craftsmanColors, bUseDesktopMode, dFrozenWidth),
                      Divider(height: 1.0, thickness: 1.0, color: craftsmanColors.m_colorBorder ?? theme.dividerColor),
                      Expanded(
                        child: ListView.builder(
                          controller: m_scrollControllerVerticalFrozen,
                          physics: const NeverScrollableScrollPhysics(),
                          itemExtent: 36.0,
                          itemCount: iTotalRecords,
                          itemBuilder: (BuildContext context, int iRowIndex) {
                            return _buildRowFrozenPaneOnly(
                                context, iRowIndex, theme, craftsmanColors, bUseDesktopMode, dFrozenWidth);
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
      ),
    );
  }

  int? m_iEditingRowIndex;

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
    // 1. Non-Editing Display Mode with Crystal Clear Focus Borders
    if (!bIsEditing) {
      return Container(
        width: 150.0,
        height: 32.0,
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          // Distinct background fill when this specific cell is focused
          color: bIsCellFocused
              ? Colors.amber.withValues(alpha: 0.30)
              : (bIsSelected ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent),
          // High-visibility amber border for cell focus, subtle divider otherwise
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

    // 2. Active Editing Mode (Text Input Active)
    final String strKey = '${iRowIndex}_$strFieldName';
    final controller = m_mapCellControllers.putIfAbsent(
      strKey,
      () => TextEditingController(text: strCellValue),
    );

    if (controller.text != strCellValue && !m_bIsDirty) {
      controller.text = strCellValue;
    }

    return Container(
      width: 150.0,
      height: 32.0,
      padding: const EdgeInsets.symmetric(horizontal: 2.0),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        border: Border.all(color: Colors.cyanAccent, width: 2.0), // Distinct cyan frame for editing
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
          contentPadding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
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

  Widget _buildDataColumnsHeader(
      List<String> lstHeaders, double dScrollableWidth, ThemeData theme, CraftsmanColors craftsmanColors) {
    return SizedBox(
      height: 36.0,
      child: Row(
        children: lstHeaders.map((strColName) {
          return Container(
            width: 150.0,
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: craftsmanColors.m_colorBorder ?? theme.dividerColor, width: 0.5)),
            ),
            child: Text(strColName, style: context.monoBoldStyle.copyWith(color: theme.colorScheme.primary)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFrozenHeaderPane(ThemeData theme, CraftsmanColors craftsmanColors, bool bUseDesktopMode, double dFrozenWidth) {
    return SizedBox(
      height: 36.0,
      child: Row(
        children: <Widget>[
          if (bUseDesktopMode)
            Container(
              width: 88.0,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor, width: 0.5))),
              child: Text(m_language.getValue('GRID_ACTIONS'),
                  style: context.monoBoldStyle.copyWith(color: theme.colorScheme.primary)),
            ),
          Container(
            width: 48.0,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor, width: 0.5))),
            child: Text('#', style: context.monoBoldStyle.copyWith(color: theme.colorScheme.primary)),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              child: Text('*',
                  style: context.monoBoldStyle.copyWith(color: craftsmanColors.m_colorZapRed ?? Colors.red, fontSize: 12.0)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowDataCellsOnly(BuildContext context, int iRowIndex, List<String> lstHeaders, double dScrollableWidth,
      ThemeData theme, CraftsmanColors craftsmanColors) {
    _ensureRowBufferedOptimized(iRowIndex);

    final Map<String, dynamic>? mapRow = m_mapRowCache[iRowIndex];
    final bool bIsLoaded = mapRow != null;
    final bool bIsZap = bIsLoaded ? (mapRow['bIsZap'] as bool) : false;
    final List<String> lstValues = bIsLoaded ? (mapRow['values'] as List<String>) : <String>[];

    final bool bIsSelected = (iRowIndex == m_iSelectedRowIndex);
    final bool bIsEditing = (iRowIndex == m_iEditingRowIndex);

    final Color colorRowBackground = bIsEditing
        ? Colors.amber.withValues(alpha: 0.22)
        : (bIsSelected
            ? Colors.blue.withValues(alpha: 0.30)
            : (iRowIndex.isEven ? theme.cardColor : theme.scaffoldBackgroundColor));

    return InkWell(
      // Synchronize row selection and C-engine pointer on row tap
      onTap: () => _selectRowAndSyncEngine(iRowIndex),
      onDoubleTap: () {
        setState(() {
          m_iSelectedRowIndex = iRowIndex;
          m_iCurrentRecNo = iRowIndex + 1;
          m_iEditingRowIndex = iRowIndex;
        });
      },
      child: Container(
        height: 36.0,
        decoration: BoxDecoration(
          color: colorRowBackground,
          border: bIsEditing
              ? Border.all(color: Colors.amber.shade700, width: 2.0)
              : Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: List<Widget>.generate(lstHeaders.length, (int iColIdx) {
              final String strColName = lstHeaders[iColIdx];
              final String strCellValue = (bIsLoaded && iColIdx < lstValues.length) ? lstValues[iColIdx] : '';
              final bool bIsCellFocused = bIsSelected && (iColIdx == m_iSelectedColIndex);

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectRowAndSyncEngine(iRowIndex, iColIndex: iColIdx),
                child: _buildCellDisplayOrInput(
                  iRowIndex: iRowIndex,
                  strFieldName: strColName,
                  strCellValue: strCellValue,
                  bIsSelected: bIsSelected,
                  bIsCellFocused: bIsCellFocused,
                  bIsEditing: bIsEditing,
                  bIsZap: bIsZap,
                  theme: theme,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildRowFrozenPaneOnly(BuildContext context, int iRowIndex, ThemeData theme, CraftsmanColors craftsmanColors,
      bool bUseDesktopMode, double dFrozenWidth) {
    final Map<String, dynamic>? mapRow = m_mapRowCache[iRowIndex];
    final bool bIsLoaded = mapRow != null;
    final int iRecNo = iRowIndex + 1;
    final bool bIsZap = bIsLoaded ? (mapRow['bIsZap'] as bool) : false;

    final bool bIsSelected = (iRowIndex == m_iSelectedRowIndex);
    final bool bIsEditing = (iRowIndex == m_iEditingRowIndex);

    final Widget widgetActionButtons = Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 18.0),
            tooltip: m_language.getValue('TOOLTIP_COMMIT_ROW'),
            onPressed: () {
              _commitRowChanges(iRowIndex);
              setState(() {
                m_iEditingRowIndex = null;
              });
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8.0),
          // Precision thin vertical divider line
          Container(
            width: 1.0,
            height: 14.0,
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8.0),
          IconButton(
            icon: Icon(
              bIsZap ? Icons.restore : Icons.delete_forever,
              color: Colors.redAccent,
              size: 18.0,
            ),
            tooltip: bIsZap ? m_language.getValue('TOOLTIP_RESTORE_ROW') : m_language.getValue('TOOLTIP_DELETE_ROW'),
            onPressed: () => _toggleDeleteSelectedRow(iRowIndex),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );

    final Color colorRowBackground = bIsEditing
        ? Colors.amber.withValues(alpha: 0.22)
        : (bIsSelected
            ? Colors.blue.withValues(alpha: 0.30)
            : (iRowIndex.isEven ? theme.cardColor : theme.scaffoldBackgroundColor));

    return InkWell(
      // Synchronize C-engine pointer when frozen header/index cells are clicked
      onTap: () => _selectRowAndSyncEngine(iRowIndex),
      child: Container(
        height: 36.0,
        color: colorRowBackground,
        child: Row(
          children: <Widget>[
            if (bUseDesktopMode)
              Container(
                width: 88.0,
                alignment: Alignment.center,
                decoration:
                    BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 0.5))),
                child: widgetActionButtons,
              ),
            Container(
              width: 48.0,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5), width: 0.5))),
              child: Text(
                '$iRecNo',
                style: context.monoStyle.copyWith(
                  color: bIsSelected ? Colors.amberAccent : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: bIsSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            Expanded(
              child: Container(
                alignment: Alignment.center,
                child: Text(bIsZap ? '*' : '', style: context.monoBoldStyle.copyWith(color: Colors.redAccent, fontSize: 12.0)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureCellInView(int iRowIndex, int iColIndex) {
    const double dRowHeight = 36.0;
    const double dColWidth = 150.0;

    // 1. Vertical view adjustment
    if (m_scrollControllerVertical.hasClients) {
      final double dTargetY = iRowIndex * dRowHeight;
      final double dMinY = m_scrollControllerVertical.offset;
      final double dViewportHeight = m_scrollControllerVertical.position.viewportDimension;
      final double dMaxY = dMinY + dViewportHeight - dRowHeight - 40.0;

      if (dTargetY < dMinY) {
        m_scrollControllerVertical.jumpTo(dTargetY.clamp(0.0, m_scrollControllerVertical.position.maxScrollExtent));
      } else if (dTargetY > dMaxY) {
        m_scrollControllerVertical.jumpTo(
            (dTargetY - dViewportHeight + dRowHeight + 60.0).clamp(0.0, m_scrollControllerVertical.position.maxScrollExtent));
      }
    }

    // 2. Horizontal view adjustment (Smooth boundary check)
    if (m_scrollControllerHorizontalBody.positions.isNotEmpty) {
      final double dTargetX = iColIndex * dColWidth;
      for (final ScrollPosition pos in m_scrollControllerHorizontalBody.positions) {
        final double dMinX = pos.pixels;
        final double dViewportWidth = pos.viewportDimension;
        final double dMaxX = dMinX + dViewportWidth - dColWidth - 50.0;

        if (dTargetX < dMinX) {
          pos.jumpTo(dTargetX.clamp(0.0, pos.maxScrollExtent));
        } else if (dTargetX > dMaxX) {
          final double dNewOffset = (dTargetX - dViewportWidth + dColWidth + 100.0).clamp(0.0, pos.maxScrollExtent);
          pos.jumpTo(dNewOffset);
        }
      }
    }
  }

  // =========================================================================
  // Performance: High-Performance Data Buffer Manager
  // =========================================================================

  static const int kChunkSize = 200;
  static const int kMaxCacheChunks = 10;

  final Map<int, Map<String, dynamic>> m_mapRowCache = <int, Map<String, dynamic>>{};
  final Set<int> m_setLoadingChunks = <int>{};
  final ValueNotifier<int> m_notifierBufferUpdate = ValueNotifier<int>(0);

  void _clearDataBuffer() {
    m_mapRowCache.clear();
    m_setLoadingChunks.clear();
    m_notifierBufferUpdate.value++;
  }

  List<VectorFieldInfo> _computeVectorLayout(List<EzField> lstFdt) {
    final List<VectorFieldInfo> listInfo = <VectorFieldInfo>[];
    int currentOffset = 0;

    for (final EzField f in lstFdt) {
      int vLen = f.len;
      if (f.type == 'N') {
        vLen = 8;
      } else if (f.type == 'L') {
        vLen = 1;
      }

      listInfo.add(VectorFieldInfo(
        field: f,
        vectorOffset: currentOffset,
        vectorLen: vLen,
      ));

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
      final int bVal = reader.intAt(info.vectorOffset, 1);
      return bVal == 1 ? 'T' : 'F';
    } else if (field.type == 'B') {
      final Uint8List rawBytes = reader.bytesAt(info.vectorOffset, info.vectorLen);
      if (rawBytes.isEmpty || rawBytes.every((int b) => b == 0)) return '';
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
      final int tagId = m_iCurrentTagId; // Provide tagId (1~8 or 0)

      // Retrieve total record count for current track (node_count for Tag, total_recs for Natural)
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

      // 1. Position cursor: Position at node iStartRec under this Tag geometry (1-based)
      m_dbService.goTo(
        iStartRec,
        iHandle: iHandle,
        tagId: tagId,
      );

      // 2. Vector fetch: C engine reads RowIDs from EDX and scatter-reads EBF to build ordered chunk
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

        // Retrieve physical EBF RowID for node (used for deletion state and row replace mapping)
        m_dbService.goTo(iCurrentTrackIndex, iHandle: iHandle, tagId: tagId);
        final int iPhysicalRowId = m_dbService.getRecNo(iHandle: iHandle, tagId: tagId);
        final bool bIsZap = m_dbService.isDeleted(iPhysicalRowId, iHandle);

        final List<String> lstValues = lstLayout.map((VectorFieldInfo info) {
          return _extractVectorFieldValue(reader, info);
        }).toList();

        m_mapRowCache[iRowIdx] = <String, dynamic>{
          'iRecNo': iPhysicalRowId, // Actual physical EBF row number
          'iTrackPos': iCurrentTrackIndex, // Order position under current Key sequence (1, 2, 3...)
          'bIsZap': bIsZap,
          'values': lstValues,
        };
      }

      m_notifierBufferUpdate.value++;
    });
  }

  void _switchToNextTab() {
    if (m_listTabs.length <= 1) return;
    final int iCurrentIndex = m_iActiveTabIndex;
    if (iCurrentIndex == -1) return;

    final int iNextIndex = (iCurrentIndex + 1) % m_listTabs.length;
    final EbfTabContext nextTab = m_listTabs[iNextIndex];

    setState(() {
      m_strActiveTabId = nextTab.strId;
      m_strActiveEbfPath = nextTab.strFilePath;
      _updateStatusBarMetrics();
    });
  }

  void _switchToPreviousTab() {
    if (m_listTabs.length <= 1) return;
    final int iCurrentIndex = m_iActiveTabIndex;
    if (iCurrentIndex == -1) return;

    final int iPrevIndex = (iCurrentIndex - 1 + m_listTabs.length) % m_listTabs.length;
    final EbfTabContext prevTab = m_listTabs[iPrevIndex];

    setState(() {
      m_strActiveTabId = prevTab.strId;
      m_strActiveEbfPath = prevTab.strFilePath;
      _updateStatusBarMetrics();
    });
  }

  // =========================================================================
  // Mobile Dock: Bottom Navigation Dock (< 600px)
  // =========================================================================

  Widget _buildMobileBottomDock(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    return BottomNavigationBar(
      key: const Key('ez_db_mobile_bottom_dock'),
      backgroundColor: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
      selectedItemColor: theme.colorScheme.primary,
      unselectedItemColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      currentIndex: 0,
      type: BottomNavigationBarType.fixed,
      selectedLabelStyle: context.uiStyle.copyWith(fontSize: 10.0),
      unselectedLabelStyle: context.uiStyle.copyWith(fontSize: 10.0),
      items: <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: const Icon(Icons.folder), label: m_language.getValue('NVBAR_OPEN')),
        BottomNavigationBarItem(icon: const Icon(Icons.search), label: m_language.getValue('NVBAR_SEEK')),
        BottomNavigationBarItem(icon: const Icon(Icons.add_box), label: m_language.getValue('NVBAR_ADD')),
        BottomNavigationBarItem(icon: const Icon(Icons.settings), label: m_language.getValue('NVBAR_SETTINGS')),
      ],
    );
  }

  // =========================================================================
  // Bottom Toolbox: Navigation Bar & Panel View Builders
  // =========================================================================

  Widget _buildBottomToolNavigationBar(BuildContext context, ThemeData theme, CraftsmanColors craftsmanColors) {
    final String? strActiveTool = m_activeTab?.strActiveBottomTool;
    final bool bIsRelationActive = (strActiveTool == 'relation');
    final bool bIsSchemaActive = (strActiveTool == 'schema');

    return Container(
      height: 36.0,
      color: craftsmanColors.m_colorHeaderBg ?? theme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        children: <Widget>[
          Icon(Icons.construction_rounded, size: 14.0, color: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary),
          const SizedBox(width: 8.0),
          Text('TOOLBOX:', style: context.uiBoldStyle.copyWith(fontSize: 10.0)),
          const SizedBox(width: 12.0),

          // Tool 1: Relation Studio
          _buildToolNavButton(
            context: context,
            theme: theme,
            icon: Icons.hub_rounded,
            label: m_language.getValue('TAB_RELATION_BUILDER'),
            isActive: bIsRelationActive,
            onTap: () => _toggleBottomTool('relation'),
          ),
          const SizedBox(width: 8.0),

          // Tool 2: Schema Designer
          _buildToolNavButton(
            context: context,
            theme: theme,
            icon: Icons.design_services_rounded,
            label: m_language.getValue('TOOLBOX_MAINTAIN_SCHEMA'),
            isActive: bIsSchemaActive,
            onTap: () => _toggleBottomTool('schema'),
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildToolNavButton({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: isActive ? Colors.amber.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4.0),
          border: Border.all(
            color: isActive ? Colors.amber.shade700 : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14.0, color: isActive ? Colors.amber.shade900 : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6.0),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.0,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.amber.shade900 : null,
              ),
            ),
            const SizedBox(width: 4.0),
            Icon(
              isActive ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
              size: 14.0,
              color: isActive ? Colors.amber.shade900 : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  /// Renders persistent bottom workbench tools using IndexedStack for tab isolation
  Widget _buildActiveBottomToolView() {
    if (m_listTabs.isEmpty || m_iActiveTabIndex < 0) {
      return const SizedBox.shrink();
    }

    return IndexedStack(
      index: m_iActiveTabIndex,
      children: m_listTabs.map((tab) {
        return TabToolchainWrapper(
          key: ValueKey('TOOLCHAIN_WRAPPER_${tab.strId}'),
          tab: tab,
          openedTabs: m_listTabs,
          onLoadEbfRequested: _handleOpenEbfDialog,
          onCollapse: () => _toggleBottomTool(null),
          onTableCreated: (String strFilePath) {
            // Convert draft tab directly if currently in draft state
            if (tab.iHandle == 0 || tab.strFilePath.isEmpty) {
              _convertDraftToOpenedEbf(tab.strId, strFilePath);
            } else {
              _openEbfFile(strFilePath);
            }
          },
        );
      }).toList(),
    );
  }
}