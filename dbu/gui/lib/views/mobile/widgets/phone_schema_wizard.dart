/* =================================================================================
 * 📁 FILE: phone_schema_wizard.dart
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * ---------------------------------------------------------------------------------
 * Phone-Specific Fullscreen Schema & Index Management Wizard (Touch-Optimized).
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
import '../../desktop/widgets/schema_designer_view.dart';

class PhoneSchemaWizard extends StatefulWidget {
  final String? strEditFilePath;
  final List<EbfTabContext> openedTabs;
  final Function(String strFilePath)? onTableCreated;

  const PhoneSchemaWizard({
    super.key,
    this.strEditFilePath,
    this.openedTabs = const <EbfTabContext>[],
    this.onTableCreated,
  });

  @override
  State<PhoneSchemaWizard> createState() => _PhoneSchemaWizardState();
}

class _PhoneSchemaWizardState extends State<PhoneSchemaWizard> with SingleTickerProviderStateMixin {
  final DbService m_dbService = DbService.instance;
  final Language m_language = Language.instance;

  late final TabController m_tabController;
  late final TextEditingController m_controllerFileName;

  late final List<TableFieldItem> m_listFields;
  late final List<TableIndexItem> m_listIndexes;
  final List<TableFieldItem> m_originalFields = <TableFieldItem>[];
  final List<TableIndexItem> m_originalIndexes = <TableIndexItem>[];

  bool get m_bIsEditMode => widget.strEditFilePath != null && widget.strEditFilePath!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    m_tabController = TabController(length: 2, vsync: this);

    if (m_bIsEditMode) {
      m_controllerFileName = TextEditingController(text: widget.strEditFilePath);
      m_listFields = <TableFieldItem>[];
      m_listIndexes = <TableIndexItem>[];
      _loadExistingSchema(widget.strEditFilePath!);
    } else {
      m_controllerFileName = TextEditingController(text: '');
      m_listFields = <TableFieldItem>[
        TableFieldItem(strName: 'ID', strType: 'I', iLength: 4, iDecimals: 0),
      ];
      m_listIndexes = <TableIndexItem>[
        TableIndexItem(strTagName: 'TAG_ID', strExpression: 'ID', bIsUnique: true),
      ];
    }

    _snapshotOriginals();
  }

  void _snapshotOriginals() {
    m_originalFields.clear();
    m_originalIndexes.clear();
    for (final f in m_listFields) {
      m_originalFields.add(f.clone());
    }
    for (final idx in m_listIndexes) {
      m_originalIndexes.add(idx.clone());
    }
  }

  void _loadExistingSchema(String strPath) {
    int hTable = 0;
    bool bNeedClose = false;

    final String normTarget = File(strPath).absolute.path.toLowerCase();
    final active = widget.openedTabs.where((t) => File(t.strFilePath).absolute.path.toLowerCase() == normTarget);

    if (active.isNotEmpty && active.first.iHandle != 0) {
      hTable = active.first.iHandle;
    } else {
      hTable = m_dbService.use(strPath, nullptr);
      bNeedClose = true;
    }

    if (hTable != 0) {
      final List<EzField> fdt = m_dbService.getFdt(iHandle: hTable);
      m_listFields.clear();
      for (final f in fdt) {
        m_listFields.add(TableFieldItem(strName: f.name, strType: f.type, iLength: f.len, iDecimals: f.dec));
      }

      final List<EzTag> tags = m_dbService.getTags(iHandle: hTable);
      m_listIndexes.clear();
      for (int i = 0; i < tags.length; i++) {
        final t = tags[i];
        final int slotId = i + 1;

        // Dynamically resolve real key expression via C-Core getIndexKey API
        String strExpr = m_dbService.getIndexKey(tagId: slotId, tagName: t.name, iHandle: hTable);
        if (strExpr.isEmpty) {
          strExpr = t.expression.isNotEmpty ? t.expression : t.name;
        }

        m_listIndexes.add(TableIndexItem(
          strTagName: t.name,
          strExpression: strExpr,
          bIsUnique: t.isUnique,
        ));
      }

      if (bNeedClose && hTable != m_dbService.m_iHandle) {
        m_dbService.close(iHandle: hTable);
      }
      _snapshotOriginals();
      setState(() {});
    }
  }

  bool _isSchemaChanged() {
    if (m_originalFields.length != m_listFields.length) return true;
    for (int i = 0; i < m_listFields.length; i++) {
      final o = m_originalFields[i];
      final c = m_listFields[i];
      if (o.strName.trim().toUpperCase() != c.strName.trim().toUpperCase() ||
          o.strType != c.strType ||
          o.iLength != c.iLength ||
          o.iDecimals != c.iDecimals) {
        return true;
      }
    }
    return false;
  }

  bool _isIndexChanged() {
    if (m_originalIndexes.length != m_listIndexes.length) return true;
    for (int i = 0; i < m_listIndexes.length; i++) {
      final o = m_originalIndexes[i];
      final c = m_listIndexes[i];
      if (o.strTagName.trim().toUpperCase() != c.strTagName.trim().toUpperCase() ||
          o.strExpression.trim().toUpperCase() != c.strExpression.trim().toUpperCase() ||
          o.bIsUnique != c.bIsUnique) {
        return true;
      }
    }
    return false;
  }

  void _openFieldEditBottomSheet({TableFieldItem? item, int? index}) {
    final bool bIsNew = (item == null);
    final TableFieldItem draft = bIsNew ? TableFieldItem(strName: 'FIELD_${m_listFields.length + 1}') : item.clone();

    final TextEditingController nameCtrl = TextEditingController(text: draft.strName);
    final TextEditingController lenCtrl = TextEditingController(text: '${draft.iLength}');
    final TextEditingController decCtrl = TextEditingController(text: '${draft.iDecimals}');
    String currentType = draft.strType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.0))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final craftsman = context.craftsmanColors;
          return Padding(
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bIsNew ? m_language.getValue('SCHEMA_BTN_ADD_FIELD') : m_language.getValue('SCHEMA_COL_NAME'),
                      style: context.uiBoldStyle.copyWith(fontSize: 14.0),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(),
                TextField(
                  controller: nameCtrl,
                  style: context.monoStyle,
                  decoration: InputDecoration(
                    labelText: m_language.getValue('SCHEMA_COL_NAME'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                DropdownButtonFormField<String>(
                  initialValue: currentType,
                  decoration: InputDecoration(
                    labelText: m_language.getValue('SCHEMA_COL_TYPE'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: <String>['C', 'N', 'I', 'D', 'L', 'B']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t, style: context.monoBoldStyle)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setSheetState(() {
                        currentType = v;
                        if (v == 'I') lenCtrl.text = '4';
                        if (v == 'B') lenCtrl.text = '24';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12.0),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: lenCtrl,
                        keyboardType: TextInputType.number,
                        style: context.monoStyle,
                        decoration: InputDecoration(
                          labelText: m_language.getValue('SCHEMA_COL_LEN'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    if (currentType == 'N') ...[
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: TextField(
                          controller: decCtrl,
                          keyboardType: TextInputType.number,
                          style: context.monoStyle,
                          decoration: const InputDecoration(
                            labelText: 'Dec',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16.0),
                SizedBox(
                  width: double.infinity,
                  height: 44.0,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: craftsman.m_colorWarmAmber ?? Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      final strName = nameCtrl.text.trim().toUpperCase();
                      if (strName.isEmpty) return;
                      final int iLen = int.tryParse(lenCtrl.text) ?? 10;
                      final int iDec = int.tryParse(decCtrl.text) ?? 0;

                      setState(() {
                        if (bIsNew) {
                          m_listFields.add(TableFieldItem(strName: strName, strType: currentType, iLength: iLen, iDecimals: iDec));
                        } else if (index != null) {
                          m_listFields[index] =
                              TableFieldItem(strName: strName, strType: currentType, iLength: iLen, iDecimals: iDec);
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text(m_language.getValue('BTN_OK'), style: context.uiBoldStyle.copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openIndexEditBottomSheet({TableIndexItem? item, int? index}) {
    final bool bIsNew = (item == null);
    final TableIndexItem draft =
        bIsNew ? TableIndexItem(strTagName: 'TAG_${m_listIndexes.length + 1}', strExpression: '') : item.clone();

    final TextEditingController tagCtrl = TextEditingController(text: draft.strTagName);
    final TextEditingController exprCtrl = TextEditingController(text: draft.strExpression);
    bool bUnique = draft.bIsUnique;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16.0))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final craftsman = context.craftsmanColors;
          return Padding(
            padding: EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              top: 16.0,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bIsNew ? m_language.getValue('SCHEMA_BTN_ADD_INDEX') : m_language.getValue('SCHEMA_TAG_NAME'),
                      style: context.uiBoldStyle.copyWith(fontSize: 14.0),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const Divider(),
                TextField(
                  controller: tagCtrl,
                  style: context.monoStyle,
                  decoration: InputDecoration(
                    labelText: m_language.getValue('SCHEMA_TAG_NAME'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                TextField(
                  controller: exprCtrl,
                  style: context.monoStyle,
                  decoration: InputDecoration(
                    labelText: m_language.getValue('SCHEMA_TAG_EXPR'),
                    hintText: m_language.getValue('SCHEMA_TAG_EXPR_HINT'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12.0),
                SwitchListTile(
                  title: Text('UNIQUE Index', style: context.uiStyle),
                  value: bUnique,
                  activeThumbColor: craftsman.m_colorWarmAmber ?? Theme.of(context).primaryColor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setSheetState(() => bUnique = v),
                ),
                const SizedBox(height: 16.0),
                SizedBox(
                  width: double.infinity,
                  height: 44.0,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: craftsman.m_colorWarmAmber ?? Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      final strTag = tagCtrl.text.trim().toUpperCase();
                      final strExpr = exprCtrl.text.trim().toUpperCase();
                      if (strTag.isEmpty || strExpr.isEmpty) return;

                      setState(() {
                        if (bIsNew) {
                          m_listIndexes.add(TableIndexItem(strTagName: strTag, strExpression: strExpr, bIsUnique: bUnique));
                        } else if (index != null) {
                          m_listIndexes[index] = TableIndexItem(strTagName: strTag, strExpression: strExpr, bIsUnique: bUnique);
                        }
                      });
                      Navigator.pop(ctx);
                    },
                    child: Text(m_language.getValue('BTN_OK'), style: context.uiBoldStyle.copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _executeSave() {
    String strFileName = m_controllerFileName.text.trim();
    if (strFileName.isNotEmpty && !strFileName.toLowerCase().endsWith('.ebf')) {
      strFileName = '$strFileName.ebf';
      m_controllerFileName.text = strFileName;
    }

    if (strFileName.isEmpty) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('SCHEMA_ERR_EMPTY_FILE_TITLE'),
        message: m_language.getValue('SCHEMA_ERR_EMPTY_FILE_MSG'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return;
    }

    final List<EzField> engineFields =
        m_listFields.map((f) => EzField(f.strName.trim().toUpperCase(), f.strType, f.iLength, f.iDecimals)).toList();

    final List<EzTag> engineTags = m_listIndexes
        .map((idx) =>
            EzTag(name: idx.strTagName.trim().toUpperCase(), expression: idx.strExpression.trim(), isUnique: idx.bIsUnique))
        .toList();

    if (m_bIsEditMode) {
      final String strDbName = strFileName.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'\.ebf$', caseSensitive: false), '');
      final int iResult = m_dbService.saveEbfSchema(
        strDbPath: strFileName,
        strDbName: strDbName,
        lstFields: engineFields,
        lstNewTags: engineTags,
        bSchemaChanged: _isSchemaChanged(),
        bIndexChanged: _isIndexChanged(),
      );

      if (iResult == 0) {
        EzNotification.showTopPanel(
          context,
          title: m_language.getValue('SCHEMA_ALTER_SUCCESS_TITLE'),
          message: '${m_language.getValue('SCHEMA_ALTER_SUCCESS_MSG')} $strFileName',
          icon: Icons.check_circle_outline_rounded,
          accentColor: Colors.green,
        );
        if (widget.onTableCreated != null) widget.onTableCreated!(strFileName);
        Navigator.pop(context);
      }
    } else {
      final int st = m_dbService.create(strFileName, engineFields);
      if (st == 0) {
        if (engineTags.isNotEmpty) {
          final int h = m_dbService.use(strFileName, nullptr);
          if (h != 0) {
            for (final t in engineTags) {
              m_dbService.createIndex(t.name, t.expression, bIsUnique: t.isUnique, iHandle: h);
            }
            m_dbService.close(iHandle: h);
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
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    m_tabController.dispose();
    m_controllerFileName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final craftsman = context.craftsmanColors;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          m_bIsEditMode ? m_language.getValue('SCHEMA_MODE_ALTER_TITLE') : m_language.getValue('SCHEMA_DESIGNER_TITLE'),
          style: context.uiBoldStyle.copyWith(fontSize: 16.0),
        ),
        backgroundColor: craftsman.m_colorHeaderBg ?? theme.cardColor,
        elevation: 0,
        bottom: TabBar(
          controller: m_tabController,
          indicatorColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
          labelColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          tabs: [
            Tab(text: '${m_language.getValue('SCHEMA_SECTION_FIELDS')} (${m_listFields.length})'),
            Tab(text: '${m_language.getValue('SCHEMA_SECTION_INDEXES')} (${m_listIndexes.length})'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12.0),
              color: craftsman.m_colorCardBg ?? theme.cardColor,
              child: TextField(
                controller: m_controllerFileName,
                enabled: !m_bIsEditMode,
                style: context.monoStyle,
                decoration: InputDecoration(
                  labelText: m_language.getValue('SCHEMA_FILE_LABEL'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: m_tabController,
                children: [
                  // Tab 1: FDT 欄位卡片清單
                  ListView.separated(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: m_listFields.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8.0),
                    itemBuilder: (context, idx) {
                      final f = m_listFields[idx];
                      return Card(
                        elevation: 0,
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: BorderSide(color: craftsman.m_colorBorder ?? theme.dividerColor, width: 0.5),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 2.0),
                          leading: CircleAvatar(
                            radius: 14.0,
                            backgroundColor: (craftsman.m_colorWarmAmber ?? theme.primaryColor).withValues(alpha: 0.15),
                            child: Text(
                              f.strType,
                              style: context.monoBoldStyle.copyWith(fontSize: 12.0, color: craftsman.m_colorWarmAmber),
                            ),
                          ),
                          title: Text(f.strName, style: context.monoBoldStyle.copyWith(fontSize: 13.0)),
                          subtitle: Text('Len: ${f.iLength}${f.strType == 'N' ? ', Dec: ${f.iDecimals}' : ''}',
                              style: context.monoCaptionStyle),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20.0),
                            onPressed: () => setState(() => m_listFields.removeAt(idx)),
                          ),
                          onTap: () => _openFieldEditBottomSheet(item: f, index: idx),
                        ),
                      );
                    },
                  ),

                  // Tab 2: EDX 索引標籤清單
                  ListView.separated(
                    padding: const EdgeInsets.all(12.0),
                    itemCount: m_listIndexes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8.0),
                    itemBuilder: (context, idx) {
                      final t = m_listIndexes[idx];
                      return Card(
                        elevation: 0,
                        color: theme.cardColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: BorderSide(color: craftsman.m_colorBorder ?? theme.dividerColor, width: 0.5),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 2.0),
                          leading: Icon(Icons.vpn_key_rounded, size: 18.0, color: craftsman.m_colorWarmAmber),
                          title: Text(t.strTagName, style: context.monoBoldStyle.copyWith(fontSize: 13.0)),
                          subtitle:
                              Text('Expr: ${t.strExpression}${t.bIsUnique ? ' (UNIQUE)' : ''}', style: context.monoCaptionStyle),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20.0),
                            onPressed: () => setState(() => m_listIndexes.removeAt(idx)),
                          ),
                          onTap: () => _openIndexEditBottomSheet(item: t, index: idx),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12.0),
              color: craftsman.m_colorHeaderBg ?? theme.cardColor,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        side: BorderSide(color: craftsman.m_colorWarmAmber ?? theme.primaryColor),
                      ),
                      onPressed: () {
                        if (m_tabController.index == 0) {
                          _openFieldEditBottomSheet();
                        } else {
                          _openIndexEditBottomSheet();
                        }
                      },
                      icon: const Icon(Icons.add, size: 16.0),
                      label: Text(m_language.getValue('MENU_ADD'), style: context.uiBoldStyle),
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                      ),
                      onPressed: _executeSave,
                      icon: const Icon(Icons.save_rounded, size: 16.0),
                      label: Text(m_language.getValue('MENU_SAVE'), style: context.uiBoldStyle.copyWith(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
