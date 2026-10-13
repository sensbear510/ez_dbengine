/* =================================================================================
 * 📁 FILE: phone_relation_wizard.dart
 * ---------------------------------------------------------------------------------
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * ---------------------------------------------------------------------------------
 * Phone-Specific Fullscreen Relation Wizard with Master-Detail Cards & Seek.
 * =================================================================================
 */

import 'package:flutter/material.dart';
import '../../../services/db_service.dart';
import '../../../services/ez_dbengine.dart';
import '../../../theme/app_theme.dart';
import '../../../toolbox/ez_notification.dart';
import '../../../toolbox/language.dart';
import '../../../toolbox/ebf_tab_context.dart';
import '../../desktop/widgets/build_relation_view.dart';

class PhoneRelationWizard extends StatefulWidget {
  final List<EbfTabContext> openedTabs;
  final EbfTabContext tab;

  const PhoneRelationWizard({
    super.key,
    required this.openedTabs,
    required this.tab,
  });

  @override
  State<PhoneRelationWizard> createState() => _PhoneRelationWizardState();
}

class _PhoneRelationWizardState extends State<PhoneRelationWizard> {
  final DbService m_dbService = DbService.instance;
  final Language m_language = Language.instance;

  int m_iCurrentStep = 0;
  int m_iJoinMode = 0; // 0: LEFT JOIN, 1: INNER JOIN

  late EbfTabContext m_selectedMasterTab;
  EbfTabContext? m_selectedSlaveTab;

  String? m_selectedMasterTagName;
  String? m_selectedSlaveTagName;

  final List<RlFieldProjectionItem> m_listProjections = <RlFieldProjectionItem>[];

  int m_hActiveRelation = 0;
  int m_iTotalRelationRecords = 0;
  final Map<int, EzRecordReader> m_mapRowCache = <int, EzRecordReader>{};
  static const int kChunkSize = 50;

  final TextEditingController m_controllerSeek = TextEditingController();

  @override
  void initState() {
    super.initState();
    m_selectedMasterTab = widget.tab;
    _rebuildFieldProjections();
  }

  @override
  void dispose() {
    m_controllerSeek.dispose();
    if (m_hActiveRelation != 0) {
      m_dbService.rlDestroyView(m_hActiveRelation);
    }
    super.dispose();
  }

  void _rebuildFieldProjections() {
    m_listProjections.clear();
    if (m_selectedMasterTab.iHandle != 0) {
      final masterFields = m_dbService.getFdt(iHandle: m_selectedMasterTab.iHandle);
      for (final f in masterFields) {
        m_listProjections.add(
          RlFieldProjectionItem(
            ebfIndex: 0,
            ebfFileName: m_selectedMasterTab.strFileName,
            fieldName: f.name,
            fieldType: f.type,
            fieldLen: f.len,
            isSelected: true,
            aliasName: f.name,
          ),
        );
      }
    }

    if (m_selectedSlaveTab != null && m_selectedSlaveTab!.iHandle != 0) {
      final slaveFields = m_dbService.getFdt(iHandle: m_selectedSlaveTab!.iHandle);
      final slavePrefix = m_selectedSlaveTab!.strFileName.split('.').first;
      for (final f in slaveFields) {
        m_listProjections.add(
          RlFieldProjectionItem(
            ebfIndex: 1,
            ebfFileName: m_selectedSlaveTab!.strFileName,
            fieldName: f.name,
            fieldType: f.type,
            fieldLen: f.len,
            isSelected: true,
            aliasName: '${slavePrefix}_${f.name}',
          ),
        );
      }
    }
  }

  void _executeBuildAndActivate() {
    if (m_selectedSlaveTab == null) {
      EzNotification.showTopPanel(
        context,
        title: m_language.getValue('REL_NOTIF_BUILD_FAIL_TITLE'),
        message: m_language.getValue('REL_CHILD_EBF_LABEL'),
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange,
      );
      return;
    }

    if (m_hActiveRelation != 0) {
      m_dbService.rlDestroyView(m_hActiveRelation);
      m_hActiveRelation = 0;
    }

    final selectedNodes = m_listProjections
        .where((item) => item.isSelected)
        .map((item) => RlNode(
              ebfIndex: item.ebfIndex,
              fieldName: item.fieldName,
              aliasName: item.aliasName,
            ))
        .toList();

    final List<RlLink> links = <RlLink>[];
    if (m_selectedSlaveTagName != null) {
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

    final desc = RlViewDesc(
      relationName: 'M_RL_VIEW',
      joinMode: m_iJoinMode,
      ebfHandles: [m_selectedMasterTab.iHandle, m_selectedSlaveTab!.iHandle],
      nodes: selectedNodes,
      links: links,
    );

    final int hRel = m_dbService.rlBuildView(desc);
    if (hRel != 0) {
      setState(() {
        m_hActiveRelation = hRel;
        m_iTotalRelationRecords = m_dbService.getRecordCount(iHandle: m_selectedMasterTab.iHandle);
        m_mapRowCache.clear();
        m_iCurrentStep = 2; // 跳至預覽步驟
      });
    }
  }

  void _ensureRowBuffered(int index) {
    if (m_mapRowCache.containsKey(index)) return;
    final int chunkId = index ~/ kChunkSize;
    final int startRecNo = chunkId * kChunkSize + 1;

    Future.microtask(() {
      if (m_mapRowCache.containsKey(index)) return;

      // 帶入 Master Tag 游標
      m_dbService.goTo(startRecNo, iHandle: m_selectedMasterTab.iHandle, tagName: m_selectedMasterTagName ?? '');

      int recSize = 0;
      for (final f in m_listProjections.where((i) => i.isSelected)) {
        recSize += f.fieldLen;
      }
      if (recSize == 0) recSize = 128;

      final readers = m_dbService.rlGetRecordVector(m_hActiveRelation, recSize, count: kChunkSize);
      for (int i = 0; i < readers.length; i++) {
        m_mapRowCache[chunkId * kChunkSize + i] = readers[i];
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final craftsman = context.craftsmanColors;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(m_language.getValue('TAB_RELATION_BUILDER'), style: context.uiBoldStyle.copyWith(fontSize: 16.0)),
        backgroundColor: craftsman.m_colorHeaderBg ?? theme.cardColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 頂部 3-Step 流程指示器
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              color: craftsman.m_colorCardBg ?? theme.cardColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStepPill(0, m_language.getValue('REL_SECTION_TABLES_JOIN')),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12.0, color: Colors.grey),
                  _buildStepPill(1, m_language.getValue('REL_SECTION_PROJECTIONS')),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 12.0, color: Colors.grey),
                  _buildStepPill(2, m_language.getValue('NVBAR_SEEK')),
                ],
              ),
            ),
            const Divider(height: 1.0),
            Expanded(
              child: IndexedStack(
                index: m_iCurrentStep,
                children: [
                  _buildStep1Pairing(theme, craftsman),
                  _buildStep2Projections(theme, craftsman),
                  _buildStep3LivePreview(theme, craftsman),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPill(int stepIndex, String title) {
    final bool isActive = (m_iCurrentStep == stepIndex);
    return InkWell(
      onTap: () {
        if (stepIndex < 2 || m_hActiveRelation != 0) {
          setState(() => m_iCurrentStep = stepIndex);
        }
      },
      child: Row(
        children: [
          CircleAvatar(
            radius: 10.0,
            backgroundColor: isActive ? Colors.amber.shade800 : Colors.grey.shade400,
            child:
                Text('${stepIndex + 1}', style: const TextStyle(fontSize: 10.0, color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 4.0),
          Text(
            title,
            style: TextStyle(
              fontSize: 11.0,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.amber.shade800 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Pairing(ThemeData theme, CraftsmanColors craftsman) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Text(m_language.getValue('REL_MASTER_EBF_LABEL'), style: context.uiBoldStyle),
        const SizedBox(height: 4.0),
        Card(
          child: ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(m_selectedMasterTab.strFileName, style: context.monoBoldStyle),
            subtitle: Text('ID: ${m_selectedMasterTab.strId}'),
          ),
        ),
        const SizedBox(height: 12.0),
        DropdownButtonFormField<String>(
          initialValue: m_selectedMasterTagName,
          decoration: InputDecoration(
            labelText: m_language.getValue('REL_MASTER_EDX_LABEL'),
            border: const OutlineInputBorder(),
          ),
          items: m_selectedMasterTab.listEdxKeys
              .map((k) =>
                  DropdownMenuItem(value: k.split(' ').first, child: Text(k, style: context.monoStyle.copyWith(fontSize: 11.0))))
              .toList(),
          onChanged: (v) => setState(() => m_selectedMasterTagName = v),
        ),
        const Divider(height: 32.0),
        Text(m_language.getValue('REL_CHILD_EBF_LABEL'), style: context.uiBoldStyle),
        const SizedBox(height: 4.0),
        DropdownButtonFormField<EbfTabContext>(
          initialValue: m_selectedSlaveTab,
          decoration: InputDecoration(
            labelText: m_language.getValue('REL_CHILD_EBF_LABEL'),
            border: const OutlineInputBorder(),
          ),
          items: widget.openedTabs
              .where((t) => t.strId != m_selectedMasterTab.strId)
              .map((t) => DropdownMenuItem(value: t, child: Text(t.strFileName, style: context.uiStyle)))
              .toList(),
          onChanged: (v) {
            setState(() {
              m_selectedSlaveTab = v;
              _rebuildFieldProjections();
            });
          },
        ),
        const SizedBox(height: 12.0),
        if (m_selectedSlaveTab != null)
          DropdownButtonFormField<String>(
            initialValue: m_selectedSlaveTagName,
            decoration: InputDecoration(
              labelText: m_language.getValue('REL_CHILD_EDX_LABEL'),
              border: const OutlineInputBorder(),
            ),
            items: m_selectedSlaveTab!.listEdxKeys
                .map((k) =>
                    DropdownMenuItem(value: k.split(' ').first, child: Text(k, style: context.monoStyle.copyWith(fontSize: 11.0))))
                .toList(),
            onChanged: (v) => setState(() => m_selectedSlaveTagName = v),
          ),
        const SizedBox(height: 24.0),
        SizedBox(
          height: 44.0,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => setState(() => m_iCurrentStep = 1),
            child: Text(m_language.getValue('BTN_NEXT'), style: context.uiBoldStyle.copyWith(color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Projections(ThemeData theme, CraftsmanColors craftsman) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12.0),
            itemCount: m_listProjections.length,
            itemBuilder: (context, idx) {
              final item = m_listProjections[idx];
              return CheckboxListTile(
                title: Text(item.aliasName, style: context.monoStyle.copyWith(fontSize: 12.0)),
                subtitle: Text('${item.ebfFileName} (${item.fieldType}, ${item.fieldLen}B)', style: context.monoCaptionStyle),
                value: item.isSelected,
                activeColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
                onChanged: (v) => setState(() => item.isSelected = v ?? false),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12.0),
          color: craftsman.m_colorHeaderBg ?? theme.cardColor,
          child: SizedBox(
            width: double.infinity,
            height: 44.0,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: craftsman.m_colorWarmAmber ?? theme.primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: _executeBuildAndActivate,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(m_language.getValue('REL_BTN_ACTIVATE'), style: context.uiBoldStyle.copyWith(color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3LivePreview(ThemeData theme, CraftsmanColors craftsman) {
    final selectedFields = m_listProjections.where((i) => i.isSelected).toList();

    return Column(
      children: [
        // 頂部檢索列
        Container(
          padding: const EdgeInsets.all(8.0),
          color: craftsman.m_colorCardBg ?? theme.cardColor,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: m_controllerSeek,
                  style: context.uiStyle,
                  decoration: const InputDecoration(
                    hintText: 'Master Key Seek...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  ),
                ),
              ),
              const SizedBox(width: 8.0),
              ElevatedButton(
                onPressed: () {
                  final key = m_controllerSeek.text.trim();
                  if (key.isEmpty || m_selectedMasterTagName == null) return;
                  final found = m_dbService.seekByName(m_selectedMasterTagName!, [key], iHandle: m_selectedMasterTab.iHandle);
                  if (found) {
                    final recNo = m_dbService.getRecNo(iHandle: m_selectedMasterTab.iHandle);
                    EzNotification.showTopPanel(context, title: 'Found', message: 'Master Key at REC #$recNo');
                  }
                },
                child: const Icon(Icons.search),
              ),
            ],
          ),
        ),
        const Divider(height: 1.0),
        // 關聯記錄卡片
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: m_iTotalRelationRecords,
            itemBuilder: (context, idx) {
              _ensureRowBuffered(idx);
              final reader = m_mapRowCache[idx];

              int currentOffset = 0;
              final List<Widget> fieldRows = [];

              for (final f in selectedFields) {
                final val = reader != null ? reader.stringAt(currentOffset, f.fieldLen) : '...';
                currentOffset += f.fieldLen;

                fieldRows.add(
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120.0,
                          child: Text(f.aliasName, style: context.monoCaptionStyle),
                        ),
                        Expanded(
                          child: Text(
                            val.isNotEmpty ? val : '(空值)',
                            style: context.monoBoldStyle.copyWith(fontSize: 12.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Card(
                elevation: 0,
                color: theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  side: BorderSide(color: craftsman.m_colorBorder ?? theme.dividerColor, width: 0.5),
                ),
                child: ExpansionTile(
                  title: Text('Relation Row #${idx + 1}', style: context.uiBoldStyle.copyWith(fontSize: 13.0)),
                  childrenPadding: const EdgeInsets.all(12.0),
                  children: fieldRows,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
