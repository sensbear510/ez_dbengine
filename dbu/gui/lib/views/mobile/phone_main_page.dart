/*
 * Copyrights (c) 2026 ezLink.io All rights reserved.
 * @ Author : CHI-HSIUNG YANG
 * @ File   : phone_main_page.dart
 */

import 'dart:ffi';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../toolbox/language.dart';
import '../../toolbox/toolbox.dart';
import '../../services/db_service.dart';
import '../../services/ez_dbengine.dart';
import '../../theme/app_theme.dart';
import 'widgets/phone_relation_wizard.dart';
import 'widgets/phone_schema_wizard.dart';
import '../../toolbox/ebf_tab_context.dart';

class PhoneMainPage extends StatefulWidget {
  final String? strInitialFilePath;
  const PhoneMainPage({super.key, this.strInitialFilePath});

  @override
  State<PhoneMainPage> createState() => _PhoneMainPageState();
}

class _PhoneMainPageState extends State<PhoneMainPage> {
  final DbService m_dbService = DbService.instance;
  final ToolBox m_toolBox = ToolBox.instance;
  final Language m_language = Language.instance;

  final List<EbfTabContext> m_listTabs = <EbfTabContext>[];
  String? m_strActiveTabId;
  int m_navIndex = 0;
  int m_iCurrentRecNo = 0;
  int m_iTotalRecs = 0;

  // 🌟 EDX Track 狀態管理：-1 代表 Natural 模式，0~7 代表 Slot 1~8
  int m_iActiveSlotIndex = -1;

  // 🌟 滑動快取管理 (Virtual Chunking)
  static const int kChunkSize = 100;
  static const int kMaxCacheChunks = 10;
  final Map<int, Map<String, dynamic>> m_mapRowCache = <int, Map<String, dynamic>>{};
  final ScrollController m_scrollController = ScrollController();

  EbfTabContext? get m_activeTab {
    if (m_strActiveTabId == null || m_listTabs.isEmpty) return null;
    return m_listTabs.firstWhere((t) => t.strId == m_strActiveTabId, orElse: () => m_listTabs.first);
  }

  /// 取得當前作用中的 tag_id (1~8)；若為 Natural 模式則傳 0
  int get m_iCurrentTagId => (m_iActiveSlotIndex >= 0 && m_iActiveSlotIndex < 8) ? (m_iActiveSlotIndex + 1) : 0;

  @override
  void initState() {
    super.initState();
    if (widget.strInitialFilePath != null && widget.strInitialFilePath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openEbf(widget.strInitialFilePath!));
    }
  }

  @override
  void dispose() {
    m_scrollController.dispose();
    super.dispose();
  }

  void _clearDataBuffer() {
    m_mapRowCache.clear();
  }

  void _openEbf(String path) {
    final norm = File(path).absolute.path;
    final handle = m_dbService.use(norm, nullptr);
    if (handle == 0) return;

    final tags = m_dbService.getTags(iHandle: handle);
    final newTab = EbfTabContext(
      strId: 'phone_${handle}_${DateTime.now().millisecondsSinceEpoch}',
      strFileName: norm.split(RegExp(r'[/\\]')).last,
      strFilePath: norm,
      iHandle: handle,
      listEdxKeys: tags.map((t) => '${t.name} (${t.expression})').toList(),
    );

    setState(() {
      m_listTabs.add(newTab);
      m_strActiveTabId = newTab.strId;
      m_iActiveSlotIndex = -1; // 預設 Natural 模式
      _clearDataBuffer();
      _refreshMetrics();
    });
  }

  void _refreshMetrics() {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
    final int h = m_activeTab!.iHandle;
    final int tagId = m_iCurrentTagId;

    setState(() {
      m_iTotalRecs = m_dbService.getLastRec(iHandle: h, tagId: tagId);
      m_iCurrentRecNo = m_iTotalRecs > 0 ? 1 : 0;
    });
  }

  /// 切換 EDX Slot 索引軌道
  void _switchEdxSlot(int slotIndex) {
    setState(() {
      if (m_iActiveSlotIndex == slotIndex) {
        m_iActiveSlotIndex = -1; // 再次點選已啟動的索引 -> 退回 Natural 物理序
      } else {
        m_iActiveSlotIndex = slotIndex;
      }
      _clearDataBuffer();
      _refreshMetrics();
      if (m_scrollController.hasClients) {
        m_scrollController.jumpTo(0.0);
      }
      m_navIndex = 0; // 自動切回「資料記錄」頁面查看重排結果
    });

    if (m_activeTab != null && m_activeTab!.iHandle != 0) {
      m_dbService.goTop(iHandle: m_activeTab!.iHandle, tagId: m_iCurrentTagId);
    }
  }

  // =========================================================================
  // ⚡ 滑動載入與 EDX 散佈組裝 (Scatter-Gather Chunking)
  // =========================================================================

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

  void _ensureRowBuffered(int targetIndex) {
    final activeTab = m_activeTab;
    if (activeTab == null || activeTab.iHandle == 0) return;
    final int recNo = targetIndex + 1;
    if (m_mapRowCache.containsKey(targetIndex)) return;

    Future.microtask(() {
      if (m_mapRowCache.containsKey(targetIndex)) return;

      final int h = activeTab.iHandle;
      final int tagId = m_iCurrentTagId;
      final int total = m_dbService.getLastRec(iHandle: h, tagId: tagId);
      if (recNo > total) return;

      final List<EzField> fdt = m_dbService.getFdt(iHandle: h);
      if (fdt.isEmpty) return;

      if (m_mapRowCache.length > kChunkSize * kMaxCacheChunks) {
        m_mapRowCache.clear();
      }

      final int startRec = recNo;
      final int countToFetch = (startRec + kChunkSize - 1 > total) ? (total - startRec + 1) : kChunkSize;
      if (countToFetch <= 0) return;

      // 🌟 依據作用中的 tagId 定位游標並進行 Vector 散佈組裝讀取
      m_dbService.goTo(startRec, iHandle: h, tagId: tagId);
      final List<EzRecordReader> readers = m_dbService.readRecordVector(
        iCount: countToFetch,
        iHandle: h,
        tagId: tagId,
      );

      final List<VectorFieldInfo> layout = _computeVectorLayout(fdt);

      for (int i = 0; i < readers.length; i++) {
        final int currentTrackPos = startRec + i;
        final int rowIdx = currentTrackPos - 1;
        final EzRecordReader reader = readers[i];

        // 查詢該節點對應的實體 RowID
        m_dbService.goTo(currentTrackPos, iHandle: h, tagId: tagId);
        final int physicalRowId = m_dbService.getRecNo(iHandle: h, tagId: tagId);
        final bool isZap = m_dbService.isDeleted(physicalRowId, h);

        final List<String> values = layout.map((info) => _extractVectorFieldValue(reader, info)).toList();

        m_mapRowCache[rowIdx] = <String, dynamic>{
          'iRecNo': physicalRowId,
          'iTrackPos': currentTrackPos,
          'bIsZap': isZap,
          'values': values,
        };
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final craftsman = context.craftsmanColors;

    final String strModeTitle = (m_iActiveSlotIndex >= 0) ? ' [EDX ${m_iActiveSlotIndex + 1}]' : ' [Natural]';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          (m_activeTab?.strFileName ?? 'ezDB Mobile') + strModeTitle,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        backgroundColor: craftsman.m_colorHeaderBg ?? theme.cardColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ebf']);
              if (res != null && res.files.single.path != null) _openEbf(res.files.single.path!);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: m_navIndex,
          children: [
            _buildDataView(theme, craftsman),
            _buildIndexSlotView(theme),
            _buildToolboxView(theme),
          ],
        ),
      ),
      floatingActionButton: m_navIndex == 0 && m_iTotalRecs > 0
          ? FloatingActionButton.small(
              onPressed: _showJumpDialog,
              child: const Icon(Icons.redo_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: m_navIndex,
        onDestinationSelected: (idx) => setState(() => m_navIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.table_rows_rounded), label: '資料記錄'),
          NavigationDestination(icon: Icon(Icons.vpn_key_rounded), label: 'EDX 索引'),
          NavigationDestination(icon: Icon(Icons.construction_rounded), label: '工具維護'),
        ],
      ),
    );
  }

  Widget _buildDataView(ThemeData theme, CraftsmanColors craftsman) {
    if (m_activeTab == null || m_activeTab!.iHandle == 0) {
      return const Center(child: Text('請點擊右上角開啟 EBF 檔案'));
    }

    final handle = m_activeTab!.iHandle;
    final fdt = m_dbService.getFdt(iHandle: handle);

    return RefreshIndicator(
      onRefresh: () async {
        _clearDataBuffer();
        _refreshMetrics();
      },
      child: ListView.separated(
        controller: m_scrollController,
        padding: const EdgeInsets.all(8),
        itemCount: m_iTotalRecs,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, idx) {
          _ensureRowBuffered(idx);

          final Map<String, dynamic>? rowData = m_mapRowCache[idx];
          final bool isLoaded = rowData != null;
          final int trackPos = idx + 1;
          final int physicalRowId = isLoaded ? rowData['iRecNo'] as int : trackPos;
          final bool isZap = isLoaded ? rowData['bIsZap'] as bool : false;
          final List<String> values = isLoaded ? rowData['values'] as List<String> : <String>[];

          final String firstColVal = values.isNotEmpty ? values[0] : (isLoaded ? '' : '載入中...');
          final String secondColVal = values.length > 1 ? values[1] : '';

          return Card(
            elevation: 0,
            color: theme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isZap ? Colors.redAccent.withValues(alpha: 0.5) : (craftsman.m_colorBorder ?? theme.dividerColor),
                width: 0.5,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: isZap ? Colors.redAccent.withValues(alpha: 0.15) : theme.primaryColor.withValues(alpha: 0.12),
                child: Text(
                  '$trackPos',
                  style: TextStyle(
                    fontSize: 11,
                    color: isZap ? Colors.redAccent : theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                fdt.isNotEmpty ? '${fdt[0].name}: $firstColVal' : 'Record #$trackPos',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: isZap ? TextDecoration.lineThrough : null,
                  color: isZap ? Colors.redAccent : null,
                ),
              ),
              subtitle: Text(
                fdt.length > 1 ? '${fdt[1].name}: $secondColVal' : 'RowID: #$physicalRowId',
                style: TextStyle(fontSize: 11, color: isZap ? Colors.red.shade300 : Colors.grey),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 18),
              onTap: isLoaded ? () => _openRecordDetailSheet(trackPos, physicalRowId, fdt, values) : null,
            ),
          );
        },
      ),
    );
  }

  void _openRecordDetailSheet(int trackPos, int physicalRowId, List<EzField> fdt, List<String> values) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('序號 #$trackPos (實體 RowID #$physicalRowId)',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: fdt.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final f = fdt[i];
                    final v = (i < values.length) ? values[i] : '';
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text(f.name, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ),
                        Expanded(
                          child: Text(
                            v.isNotEmpty ? v : '(空值)',
                            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildIndexSlotView(ThemeData theme) {
    final keys = m_activeTab?.listEdxKeys ?? [];
    if (keys.isEmpty) return const Center(child: Text('無 EDX 索引'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: keys.length,
      itemBuilder: (_, i) {
        final bool isCurrent = (m_iActiveSlotIndex == i);
        return Card(
          elevation: 0,
          color: isCurrent ? theme.primaryColor.withValues(alpha: 0.12) : theme.cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isCurrent ? theme.primaryColor : theme.dividerColor.withValues(alpha: 0.5),
              width: isCurrent ? 1.5 : 0.5,
            ),
          ),
          child: ListTile(
            leading: Icon(
              Icons.vpn_key_rounded,
              color: isCurrent ? theme.primaryColor : Colors.grey,
            ),
            title: Text(
              'Slot ${i + 1}${isCurrent ? ' (作用中)' : ''}',
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                color: isCurrent ? theme.primaryColor : null,
              ),
            ),
            subtitle: Text(keys[i]),
            trailing: isCurrent ? const Icon(Icons.check_circle_rounded, color: Colors.green) : null,
            onTap: () => _switchEdxSlot(i),
          ),
        );
      },
    );
  }

  Widget _buildToolboxView(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(
          leading: const Icon(Icons.schema_rounded),
          title: Text(m_language.getValue('TOOLBOX_MAINTAIN_SCHEMA')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => PhoneSchemaWizard(
                  strEditFilePath: m_activeTab?.strFilePath,
                  openedTabs: m_listTabs,
                  onTableCreated: (path) => _openEbf(path),
                ),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.hub_rounded),
          title: Text(m_language.getValue('TAB_RELATION_BUILDER')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            if (m_activeTab == null || m_activeTab!.iHandle == 0) return;
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => PhoneRelationWizard(
                  openedTabs: m_listTabs,
                  tab: m_activeTab!,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _showJumpDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳轉記錄 (Go To)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $m_iTotalRecs'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final target = int.tryParse(ctrl.text);
              if (target != null && target >= 1 && target <= m_iTotalRecs) {
                Navigator.pop(ctx);
                final double targetOffset = (target - 1) * 72.0; // 72.0 為手機版 Card 約略高度
                if (m_scrollController.hasClients) {
                  m_scrollController.jumpTo(
                    targetOffset.clamp(0.0, m_scrollController.position.maxScrollExtent),
                  );
                }
              }
            },
            child: const Text('跳轉'),
          ),
        ],
      ),
    );
  }
}
