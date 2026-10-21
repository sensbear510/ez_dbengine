/* =================================================================================
 * 📁 FILE: schema_designer_view.dart
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * ---------------------------------------------------------------------------------
 * Workbench Panel for Visualizing EZ_FIELD_NODE and EDX Index Creation / Alteration.
 * =================================================================================
 */

import 'dart:ffi';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../../services/db_service.dart';
import '../../../services/ez_dbengine.dart';
import '../../../theme/app_theme.dart';
import '../../../toolbox/ez_notification.dart';
import '../../../toolbox/language.dart';
import '../../../toolbox/ebf_tab_context.dart';

/// Model representing a table field definition
class TableFieldItem {
  String strName;
  String strType; // 'C', 'N', 'I', 'D', 'L', 'B'
  int iLength;
  int iDecimals;

  TableFieldItem({
    required this.strName,
    this.strType = 'C',
    this.iLength = 10,
    this.iDecimals = 0,
  });

  TableFieldItem clone() => TableFieldItem(
        strName: strName,
        strType: strType,
        iLength: iLength,
        iDecimals: iDecimals,
      );
}

/// Model representing an EDX index tag definition
class TableIndexItem {
  String strTagName;
  String strExpression;
  bool bIsUnique;

  TableIndexItem({
    required this.strTagName,
    required this.strExpression,
    this.bIsUnique = false,
  });

  TableIndexItem clone() => TableIndexItem(
        strTagName: strTagName,
        strExpression: strExpression,
        bIsUnique: bIsUnique,
      );
}

/// Craftsman Visual Schema & Index Workbench View
class SchemaDesignerView extends StatefulWidget {
  final VoidCallback? onCollapse;
  final Function(String strFilePath)? onTableCreated;

  /// Callback requesting parent container to open Modal File Dialog for loading EBF
  final VoidCallback? onLoadEbfRequested;

  /// Path to existing EBF file if opened in "Alter Mode"
  final String? strEditFilePath;

  /// List of opened EBF tabs used for save conflict validation
  final List<EbfTabContext> openedTabs;

  const SchemaDesignerView({
    super.key,
    this.onCollapse,
    this.onTableCreated,
    this.onLoadEbfRequested,
    this.strEditFilePath,
    this.openedTabs = const <EbfTabContext>[],
  });

  @override
  State<SchemaDesignerView> createState() => SchemaDesignerViewState();
}

class SchemaDesignerViewState extends State<SchemaDesignerView> {
  final DbService m_dbService = DbService.instance;
  final Language m_language = Language.instance;

  late final TextEditingController m_controllerFileName;

  // Independent scroll controllers for fields and indexes lists
  final ScrollController m_scrollControllerFields = ScrollController();
  final ScrollController m_scrollControllerIndexes = ScrollController();

  late final List<TableFieldItem> m_listFields;
  late final List<TableIndexItem> m_listIndexes;

  // Snapshots for detecting structure and index changes in ALTER mode
  final List<TableFieldItem> m_originalFields = <TableFieldItem>[];
  final List<TableIndexItem> m_originalIndexes = <TableIndexItem>[];

  bool get m_bIsEditMode => widget.strEditFilePath != null && widget.strEditFilePath!.isNotEmpty;

  /// Public getter to check if schema or index tags have unsaved changes
  bool get isDirty => _isSchemaChanged() || _isIndexChanged();

  @override
  void initState() {
    super.initState();

    if (m_bIsEditMode) {
      // Mode 2: Alter Mode - Initialize with existing database structure
      m_controllerFileName = TextEditingController(text: widget.strEditFilePath);
      m_listFields = <TableFieldItem>[];
      m_listIndexes = <TableIndexItem>[];
      _loadExistingTableSchema(widget.strEditFilePath!);
    } else {
      // Mode 1: Create Mode - Default to empty filename and 1 initial field row
      m_controllerFileName = TextEditingController(text: '');
      m_listFields = <TableFieldItem>[
        TableFieldItem(strName: 'ID', strType: 'I', iLength: 4, iDecimals: 0),
      ];
      m_listIndexes = <TableIndexItem>[
        TableIndexItem(strTagName: 'TAG_ID', strExpression: 'ID', bIsUnique: true),
      ];
    }

    // Synchronously initialize snapshots to prevent false dirty status upon initialization
    m_originalFields.clear();
    m_originalIndexes.clear();
    for (final f in m_listFields) {
      m_originalFields.add(f.clone());
    }
    for (final idx in m_listIndexes) {
      m_originalIndexes.add(idx.clone());
    }
  }

  @override
  void didUpdateWidget(covariant SchemaDesignerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.strEditFilePath != widget.strEditFilePath) {
      m_controllerFileName.text = widget.strEditFilePath ?? '';

      m_listFields.clear();
      m_listIndexes.clear();
      m_originalFields.clear();
      m_originalIndexes.clear();

      if (m_bIsEditMode) {
        // Alter Mode: Load FDT and EDX tags of selected EBF
        _loadExistingTableSchema(widget.strEditFilePath!);
      } else {
        // Create Mode: Reset to initial draft state
        m_listFields.add(TableFieldItem(strName: 'ID', strType: 'I', iLength: 4, iDecimals: 0));
        m_listIndexes.add(TableIndexItem(strTagName: 'TAG_ID', strExpression: 'ID', bIsUnique: true));
        for (final f in m_listFields) {
          m_originalFields.add(f.clone());
        }
        for (final idx in m_listIndexes) {
          m_originalIndexes.add(idx.clone());
        }
        setState(() {});
      }
    }
  }

  /// Inspects and loads existing schema fields & EDX tags from active database handle
  void _loadExistingTableSchema(String strPath) {
    try {
      int hTable = 0;
      bool bNeedCloseTemporaryHandle = false;

      final String strTargetNormalized = File(strPath).absolute.path.toLowerCase();

      // Check if DbService already holds active handle for this file
      final Iterable<EbfTabContext> activeMatches =
          widget.openedTabs.where((tab) => File(tab.strFilePath).absolute.path.toLowerCase() == strTargetNormalized);

      if (activeMatches.isNotEmpty && activeMatches.first.iHandle != 0) {
        hTable = activeMatches.first.iHandle;
      } else {
        // Attempt opening temporary handle only if not active in main window
        hTable = m_dbService.use(strPath, nullptr);
        bNeedCloseTemporaryHandle = true;
      }

      if (hTable != 0) {
        // Load physical FDT fields
        final List<EzField> lstFdt = m_dbService.getFdt(iHandle: hTable);
        m_listFields.clear();
        m_originalFields.clear();

        for (final field in lstFdt) {
          final item = TableFieldItem(
            strName: field.name,
            strType: field.type,
            iLength: field.len,
            iDecimals: field.dec,
          );
          m_listFields.add(item);
          m_originalFields.add(item.clone());
        }

        // Load existing EDX index tags
        final List<EzTag> lstTags = m_dbService.getTags(iHandle: hTable);
        m_listIndexes.clear();
        m_originalIndexes.clear();

        for (int i = 0; i < lstTags.length; i++) {
          final tag = lstTags[i];
          final int slotId = i + 1;

          String strExpr = m_dbService.getIndexKey(tagId: slotId, tagName: tag.name, iHandle: hTable);
          if (strExpr.isEmpty) {
            strExpr = tag.expression.isNotEmpty ? tag.expression : tag.name;
          }

          final item = TableIndexItem(
            strTagName: tag.name,
            strExpression: strExpr,
            bIsUnique: tag.isUnique,
          );
          m_listIndexes.add(item);
          m_originalIndexes.add(item.clone());
        }

        if (bNeedCloseTemporaryHandle && hTable != m_dbService.m_iHandle) {
          m_dbService.close(iHandle: hTable);
        }

        setState(() {});
      } else {
        debugPrint('[SchemaDesignerView] Failed to acquire database handle for path: $strPath');
      }
    } catch (e) {
      debugPrint('[SchemaDesignerView] Failed to inspect existing schema/tags: $e');
    }
  }

  /// Evaluates whether physical table schema (FDT) has changed
  bool _isSchemaChanged() {
    if (m_originalFields.length != m_listFields.length) return true;
    for (int i = 0; i < m_listFields.length; i++) {
      final orig = m_originalFields[i];
      final curr = m_listFields[i];
      if (orig.strName.trim().toUpperCase() != curr.strName.trim().toUpperCase() ||
          orig.strType != curr.strType ||
          orig.iLength != curr.iLength ||
          orig.iDecimals != curr.iDecimals) {
        return true;
      }
    }
    return false;
  }

  /// Evaluates whether EDX index tags have changed
  bool _isIndexChanged() {
    if (m_originalIndexes.length != m_listIndexes.length) return true;
    for (int i = 0; i < m_listIndexes.length; i++) {
      final orig = m_originalIndexes[i];
      final curr = m_listIndexes[i];
      if (orig.strTagName.trim().toUpperCase() != curr.strTagName.trim().toUpperCase() ||
          orig.strExpression.trim().toUpperCase() != curr.strExpression.trim().toUpperCase() ||
          orig.bIsUnique != curr.bIsUnique) {
        return true;
      }
    }
    return false;
  }

  /// Appends a new blank field row
  void _addNewField() {
    setState(() {
      m_listFields.add(TableFieldItem(strName: 'FIELD_${m_listFields.length + 1}'));
    });
  }

  /// Appends a new blank index row
  void _addNewIndex() {
    setState(() {
      m_listIndexes.add(TableIndexItem(strTagName: 'TAG_${m_listIndexes.length + 1}', strExpression: ''));
    });
  }

  /// Universal validator checking file name, field rules, index tag rules, and open tab conflicts
  bool _validateSchemaInput(String strFileName) {
    if (strFileName.isEmpty) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_EMPTY_FILE_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_EMPTY_FILE_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return false;
    }

    // [DEFENSE GATE 1]: Resolve absolute path to prevent relative path bypass
    final File targetFile = File(strFileName);
    final String strAbsolutePath = targetFile.absolute.path;
    final String strNormalizedTarget = strAbsolutePath.toLowerCase();

    // [DEFENSE GATE 2]: Validate target filename conflict against active opened tabs
    final bool bIsConflict = widget.openedTabs.any((tab) {
      // Skip validation against itself if operating in Alter Mode
      if (m_bIsEditMode && widget.strEditFilePath != null) {
        if (File(tab.strFilePath).absolute.path.toLowerCase() == File(widget.strEditFilePath!).absolute.path.toLowerCase()) {
          return false;
        }
      }

      // Skip draft tabs that have no physical path yet
      if (tab.strFilePath.isEmpty) return false;

      // Compare absolute physical paths safely
      return File(tab.strFilePath).absolute.path.toLowerCase() == strNormalizedTarget;
    });

    if (bIsConflict) {
      final String strMsg = m_language.getValue('SCHEMA_MSG_SAVE_CONFLICT').replaceAll('{filename}', strFileName);

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_TITLE_SAVE_CONFLICT'),
        message: strMsg,
        icon: Icons.block_rounded,
        accentColor: Colors.red,
      );
      return false;
    }

    // [DEFENSE GATE 3]: Prevent overwriting existing physical files (Create Mode ONLY)
    if (!m_bIsEditMode && targetFile.existsSync()) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_FILE_EXISTS_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_FILE_EXISTS_MSG'),
        icon: Icons.error_outline_rounded,
        accentColor: Colors.red,
      );
      return false;
    }

    if (m_listFields.isEmpty) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_NO_FIELDS_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_NO_FIELDS_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return false;
    }

    if (m_listFields.length >= 90) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_MAX_FIELDS_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_MAX_FIELDS_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return false;
    }

    if (m_listIndexes.length >= 8) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_MAX_TAGS_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_MAX_TAGS_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return false;
    }

    final Set<String> setFieldNames = <String>{};
    for (int i = 0; i < m_listFields.length; i++) {
      final f = m_listFields[i];
      final String strName = f.strName.trim().toUpperCase();

      if (strName.isEmpty) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_BLANK_FIELD_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_BLANK_FIELD_MSG')} #${i + 1}',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (f.iLength <= 0) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_INVALID_LEN_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_INVALID_LEN_MSG')} [$strName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (strName.length > 52) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_LONG_FIELD_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_LONG_FIELD_MSG')} [$strName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (setFieldNames.contains(strName)) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_DUP_FIELD_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_DUP_FIELD_MSG')}: [$strName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (f.strType == 'B' && f.iLength < 24) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_BLOB_LEN_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_BLOB_LEN_MSG')} [$strName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      setFieldNames.add(strName);
    }

    final Set<String> setTagNames = <String>{};
    for (int i = 0; i < m_listIndexes.length; i++) {
      final idx = m_listIndexes[i];
      final String strTagName = idx.strTagName.trim().toUpperCase();
      final String strExpr = idx.strExpression.trim().toUpperCase();

      if (strTagName.isEmpty) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_BLANK_TAG_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_BLANK_TAG_MSG')} #${i + 1}',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (strExpr.isEmpty) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_BLANK_EXPR_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_BLANK_EXPR_MSG')} [$strTagName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }

      if (setTagNames.contains(strTagName)) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ERR_DUP_TAG_TITLE'),
          message: '${m_language.getValue('SCHEMA_ERR_DUP_TAG_MSG')}: [$strTagName]',
          icon: Icons.warning_amber_rounded,
          accentColor: Colors.orange,
        );
        return false;
      }
      setTagNames.add(strTagName);

      final List<String> lstExprFields = strExpr.split('+').map((s) => s.trim()).toList();
      for (final String exprField in lstExprFields) {
        final TableFieldItem? matchedField = m_listFields.cast<TableFieldItem?>().firstWhere(
              (f) => f?.strName.trim().toUpperCase() == exprField,
              orElse: () => null,
            );
        if (matchedField != null && matchedField.strType == 'B') {
          EzNotification.showTopPanel(
            context,
            title: m_language.getValue('SCHEMA_ERR_BLOB_INDEX_TITLE'),
            message: '${m_language.getValue('SCHEMA_ERR_BLOB_INDEX_MSG')} [$exprField]',
            icon: Icons.warning_amber_rounded,
            accentColor: Colors.orange,
          );
          return false;
        }
      }
    }

    return true;
  }

  /// Dispatcher method handling Creation or Alteration pipeline
  void _executeSave() {
    String strFileName = m_controllerFileName.text.trim();
    if (strFileName.isNotEmpty && !strFileName.toLowerCase().endsWith('.ebf')) {
      strFileName = '$strFileName.ebf';
      m_controllerFileName.text = strFileName;
    }

    if (!_validateSchemaInput(strFileName)) return;

    if (m_bIsEditMode) {
      _executeAlterDatabase(strFileName);
    } else {
      _executeCreateDatabase(strFileName);
    }
  }

  /// Pipeline 1: Create brand new EBF database
  void _executeCreateDatabase(String strFileName) {
    try {
      final List<EzField> lstEngineFields = m_listFields.map((f) {
        return EzField(f.strName.trim().toUpperCase(), f.strType, f.iLength, f.iDecimals);
      }).toList();

      final int iCreateStatus = m_dbService.create(strFileName, lstEngineFields);
      if (iCreateStatus != 0) {
        throw Exception('Engine create failed with status code: $iCreateStatus');
      }

      if (m_listIndexes.isNotEmpty) {
        final int hTable = m_dbService.use(strFileName, nullptr);
        if (hTable > 0) {
          try {
            for (final idx in m_listIndexes) {
              m_dbService.createIndex(
                idx.strTagName.trim().toUpperCase(),
                idx.strExpression.trim(),
                bIsUnique: idx.bIsUnique,
                iHandle: hTable,
              );
            }
          } finally {
            m_dbService.close(iHandle: hTable);
          }
        }
      }

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_SUCCESS_TITLE'),
        message: '${m_language.getValue('SCHEMA_SUCCESS_MSG')} $strFileName',
        icon: Icons.check_circle_outline_rounded,
        accentColor: Colors.green,
      );

      if (widget.onTableCreated != null) widget.onTableCreated!(strFileName);
      if (widget.onCollapse != null) widget.onCollapse!();
    } catch (e) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_CREATE_FAIL_TITLE'),
        message: 'Creation Failed: $e',
        icon: Icons.error_outline_rounded,
        accentColor: Colors.red,
      );
    }
  }

  /// Pipeline 2: Alter existing EBF database schema and sync EDX tags via DbService
  void _executeAlterDatabase(String strFileName) {
    final bool bSchemaChanged = _isSchemaChanged();
    final bool bIndexChanged = _isIndexChanged();

    if (!bSchemaChanged && !bIndexChanged) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_NOTIF_NO_CHANGES_TITLE'),
        message: m_language.getValue('SCHEMA_NOTIF_NO_CHANGES_MSG'),
        icon: Icons.info_outline_rounded,
        accentColor: Colors.blue,
      );
      return;
    }

    try {
      final String strDbName = strFileName.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.ebf$', caseSensitive: false), '');

      final List<EzField> lstEngineFields = m_listFields.map((f) {
        return EzField(f.strName.trim().toUpperCase(), f.strType, f.iLength, f.iDecimals);
      }).toList();

      final List<EzTag> lstNewTags = m_listIndexes.map((idx) {
        return EzTag(
          name: idx.strTagName.trim().toUpperCase(),
          expression: idx.strExpression.trim(),
          isUnique: idx.bIsUnique,
        );
      }).toList();

      // 🛡️ SECURITY PATCH: Sync Alter pipeline handle strictly with UI Tab Collection
      int? iActiveHandle;
      final String strTargetNormalized = File(strFileName).absolute.path.toLowerCase();
      final Iterable<EbfTabContext> activeMatches =
          widget.openedTabs.where((tab) => File(tab.strFilePath).absolute.path.toLowerCase() == strTargetNormalized);

      if (activeMatches.isNotEmpty) {
        iActiveHandle = activeMatches.first.iHandle;
      }

      final int iResult = m_dbService.saveEbfSchema(
        strDbPath: strFileName,
        strDbName: strDbName,
        lstFields: lstEngineFields,
        lstNewTags: lstNewTags,
        bSchemaChanged: bSchemaChanged,
        bIndexChanged: bIndexChanged,
        iHandle: iActiveHandle,
      );

      if (iResult != 0) {
        throw Exception('saveEbfSchema failed with status code: $iResult');
      }

      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ALTER_SUCCESS_TITLE'),
        message: '${m_language.getValue('SCHEMA_ALTER_SUCCESS_MSG')} $strFileName',
        icon: Icons.check_circle_outline_rounded,
        accentColor: Colors.green,
      );

      if (widget.onTableCreated != null) widget.onTableCreated!(strFileName);
      if (widget.onCollapse != null) widget.onCollapse!();
    } catch (e) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_CREATE_FAIL_TITLE'),
        message: 'Alteration Failed: $e',
        icon: Icons.error_outline_rounded,
        accentColor: Colors.red,
      );
    }
  }

  /// Helper builder for rendering localized field type reference items
  Widget _buildTypeGuideItem(String strKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3.0),
      child: Text(
        m_language.getValue(strKey),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 10.0,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
      ),
    );
  }

  @override
  void dispose() {
    m_controllerFileName.dispose();
    m_scrollControllerFields.dispose();
    m_scrollControllerIndexes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final CraftsmanColors craftsmanColors = context.craftsmanColors;

    final bool bIsFieldsEmpty = m_listFields.isEmpty;
    final bool bIsIndexesEmpty = m_listIndexes.isEmpty;

    return Row(
      children: <Widget>[
        // Left Panel: Table File & Settings Configuration (380px)
        Container(
          width: 380.0,
          color: theme.cardColor,
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    m_bIsEditMode ? m_language.getValue('SCHEMA_MODE_ALTER_TITLE') : m_language.getValue('SCHEMA_DESIGNER_TITLE'),
                    style: context.uiBoldStyle.copyWith(fontSize: 13.0),
                  ),
                  if (widget.onCollapse != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 26.0),
                      onPressed: widget.onCollapse,
                      tooltip: m_language.getValue('SCHEMA_TOOLTIP_CLOSE'),
                      padding: const EdgeInsets.all(4.0),
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
              const SizedBox(height: 8.0),

              // EBF File Path Input + "Load EBF" Button
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: m_controllerFileName,
                      enabled: !m_bIsEditMode,
                      style: context.uiStyle,
                      decoration: InputDecoration(
                        labelText: m_language.getValue('SCHEMA_FILE_LABEL'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 14.0),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.onLoadEbfRequested,
                    icon: const Icon(Icons.folder_open_rounded, size: 14.0),
                    label: Text(
                      m_language.getValue('SCHEMA_BTN_LOAD_EBF'),
                      style: const TextStyle(fontSize: 11.0),
                    ),
                  ),
                ],
              ),
              const Divider(height: 16.0),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(m_language.getValue('SCHEMA_GUIDE_TITLE'),
                          style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: craftsmanColors.m_colorWarmAmber)),
                      const SizedBox(height: 4.0),
                      Text(
                        m_language.getValue('SCHEMA_GUIDE_DESC'),
                        style: context.uiStyle.copyWith(fontSize: 10.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                      ),
                      const Divider(height: 16.0),
                      // Field Types Reference Section
                      Text(m_language.getValue('SCHEMA_TYPES_TITLE'),
                          style: context.uiBoldStyle.copyWith(fontSize: 11.0, color: craftsmanColors.m_colorWarmAmber)),
                      const SizedBox(height: 6.0),
                      _buildTypeGuideItem('SCHEMA_TYPE_C'),
                      _buildTypeGuideItem('SCHEMA_TYPE_N'),
                      _buildTypeGuideItem('SCHEMA_TYPE_I'),
                      _buildTypeGuideItem('SCHEMA_TYPE_D'),
                      _buildTypeGuideItem('SCHEMA_TYPE_L'),
                      _buildTypeGuideItem('SCHEMA_TYPE_B'),
                      const Divider(height: 16.0),
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          m_language.getValue('GUIDE_COMBINED_KEY'),
                          style: context.uiStyle.copyWith(
                            fontSize: 11.0,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8.0),
              SizedBox(
                width: double.infinity,
                height: 40.0,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: craftsmanColors.m_colorWarmAmber ?? theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _executeSave,
                  icon: Icon(m_bIsEditMode ? Icons.save_rounded : Icons.bolt_rounded, size: 16.0),
                  label: Text(
                    m_bIsEditMode ? m_language.getValue('SCHEMA_BTN_SAVE_EBF') : m_language.getValue('SCHEMA_BTN_GENERATE'),
                    style: context.uiBoldStyle.copyWith(color: Colors.white, fontSize: 12.0),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Panel: Visual Workbench Grid for Fields & Indexes
        Expanded(
          child: Container(
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 1. EZ_FIELD_NODE Section (Flex Ratio = 3)
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(m_language.getValue('SCHEMA_SECTION_FIELDS'),
                              style: context.uiBoldStyle.copyWith(fontSize: 12.0, color: theme.colorScheme.primary)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: bIsFieldsEmpty ? (craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade800) : null,
                              foregroundColor: bIsFieldsEmpty ? Colors.white : null,
                              elevation: bIsFieldsEmpty ? 4.0 : 0.0,
                            ),
                            onPressed: _addNewField,
                            icon: Icon(
                              Icons.add,
                              size: 14.0,
                              color: bIsFieldsEmpty ? Colors.white : null,
                            ),
                            label: Text(
                              m_language.getValue('SCHEMA_BTN_ADD_FIELD'),
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: bIsFieldsEmpty ? FontWeight.bold : FontWeight.normal,
                                color: bIsFieldsEmpty ? Colors.white : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: bIsFieldsEmpty
                                  ? (craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade700)
                                  : (craftsmanColors.m_colorBorder ?? theme.dividerColor),
                              width: bIsFieldsEmpty ? 1.5 : 1.0,
                            ),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: m_listFields.isEmpty
                              ? Center(
                                  child: Text(
                                    m_language.getValue('SCHEMA_EMPTY_FIELDS_HINT'),
                                    style: context.uiStyle.copyWith(
                                      fontSize: 11.0,
                                      color: craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Scrollbar(
                                  controller: m_scrollControllerFields,
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    controller: m_scrollControllerFields,
                                    itemCount: m_listFields.length,
                                    itemBuilder: (context, index) {
                                      final field = m_listFields[index];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
                                        ),
                                        child: Row(
                                          children: <Widget>[
                                            Text('${index + 1}.', style: context.monoStyle.copyWith(fontSize: 10.0)),
                                            const SizedBox(width: 8.0),
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: TextEditingController(text: field.strName)
                                                  ..selection = TextSelection.collapsed(offset: field.strName.length),
                                                style: context.monoStyle.copyWith(fontSize: 11.0),
                                                decoration: InputDecoration(
                                                    labelText: m_language.getValue('SCHEMA_COL_NAME'),
                                                    isDense: true,
                                                    border: const UnderlineInputBorder()),
                                                onChanged: (val) => field.strName = val,
                                              ),
                                            ),
                                            const SizedBox(width: 12.0),
                                            Expanded(
                                              flex: 2,
                                              child: DropdownButtonFormField<String>(
                                                initialValue: field.strType,
                                                isDense: true,
                                                decoration: InputDecoration(
                                                    labelText: m_language.getValue('SCHEMA_COL_TYPE'), isDense: true),
                                                items: <String>['C', 'N', 'I', 'D', 'L', 'B']
                                                    .map((t) => DropdownMenuItem(
                                                        value: t, child: Text(t, style: const TextStyle(fontSize: 11.0))))
                                                    .toList(),
                                                onChanged: (val) => setState(() => field.strType = val ?? 'C'),
                                              ),
                                            ),
                                            const SizedBox(width: 12.0),
                                            Expanded(
                                              flex: 2,
                                              child: TextField(
                                                controller: TextEditingController(text: '${field.iLength}'),
                                                keyboardType: TextInputType.number,
                                                style: context.monoStyle.copyWith(fontSize: 11.0),
                                                decoration: InputDecoration(
                                                    labelText: m_language.getValue('SCHEMA_COL_LEN'),
                                                    isDense: true,
                                                    border: const UnderlineInputBorder()),
                                                onChanged: (val) => field.iLength = int.tryParse(val) ?? 10,
                                              ),
                                            ),
                                            const SizedBox(width: 8.0),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 16.0, color: Colors.redAccent),
                                              onPressed: () => setState(() => m_listFields.removeAt(index)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12.0),

                // 2. EDX Index Builder Section (Flex Ratio = 2)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(m_language.getValue('SCHEMA_SECTION_INDEXES'),
                              style: context.uiBoldStyle.copyWith(fontSize: 12.0, color: craftsmanColors.m_colorWarmAmber)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: bIsIndexesEmpty ? (craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade800) : null,
                              foregroundColor: bIsIndexesEmpty ? Colors.white : null,
                              elevation: bIsIndexesEmpty ? 4.0 : 0.0,
                            ),
                            onPressed: _addNewIndex,
                            icon: Icon(
                              Icons.add,
                              size: 14.0,
                              color: bIsIndexesEmpty ? Colors.white : null,
                            ),
                            label: Text(
                              m_language.getValue('SCHEMA_BTN_ADD_INDEX'),
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: bIsIndexesEmpty ? FontWeight.bold : FontWeight.normal,
                                color: bIsIndexesEmpty ? Colors.white : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6.0),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: bIsIndexesEmpty
                                  ? (craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade700)
                                  : (craftsmanColors.m_colorBorder ?? theme.dividerColor),
                              width: bIsIndexesEmpty ? 1.5 : 1.0,
                            ),
                            borderRadius: BorderRadius.circular(4.0),
                          ),
                          child: m_listIndexes.isEmpty
                              ? Center(
                                  child: Text(
                                    m_language.getValue('SCHEMA_EMPTY_INDEXES_HINT'),
                                    style: context.uiStyle.copyWith(
                                      fontSize: 11.0,
                                      color: craftsmanColors.m_colorWarmAmber ?? Colors.amber.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : Scrollbar(
                                  controller: m_scrollControllerIndexes,
                                  thumbVisibility: true,
                                  child: ListView.builder(
                                    controller: m_scrollControllerIndexes,
                                    itemCount: m_listIndexes.length,
                                    itemBuilder: (context, index) {
                                      final idx = m_listIndexes[index];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3))),
                                        ),
                                        child: Row(
                                          children: <Widget>[
                                            Text('Tag ${index + 1}.', style: context.monoStyle.copyWith(fontSize: 10.0)),
                                            const SizedBox(width: 8.0),
                                            Expanded(
                                              flex: 3,
                                              child: TextField(
                                                controller: TextEditingController(text: idx.strTagName)
                                                  ..selection = TextSelection.collapsed(offset: idx.strTagName.length),
                                                style: context.monoStyle.copyWith(fontSize: 11.0),
                                                decoration: InputDecoration(
                                                    labelText: m_language.getValue('SCHEMA_TAG_NAME'),
                                                    isDense: true,
                                                    border: const UnderlineInputBorder()),
                                                onChanged: (val) => idx.strTagName = val,
                                              ),
                                            ),
                                            const SizedBox(width: 12.0),
                                            Expanded(
                                              flex: 4,
                                              child: TextField(
                                                controller: TextEditingController(text: idx.strExpression)
                                                  ..selection = TextSelection.collapsed(offset: idx.strExpression.length),
                                                style: context.monoStyle.copyWith(fontSize: 11.0),
                                                decoration: InputDecoration(
                                                  labelText: m_language.getValue('SCHEMA_TAG_EXPR'),
                                                  hintText: m_language.getValue('SCHEMA_TAG_EXPR_HINT'),
                                                  hintStyle: context.uiStyle.copyWith(
                                                      fontSize: 10.0, color: theme.colorScheme.onSurface.withValues(alpha: 0.35)),
                                                  isDense: true,
                                                  border: const UnderlineInputBorder(),
                                                ),
                                                onChanged: (val) => idx.strExpression = val,
                                              ),
                                            ),
                                            const SizedBox(width: 8.0),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, size: 16.0, color: Colors.redAccent),
                                              onPressed: () => setState(() => m_listIndexes.removeAt(index)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
