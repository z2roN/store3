import 'package:flutter/material.dart';
import '../api.dart';
import '../pricing.dart';
import 'common.dart';
import 'scan.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> with SingleTickerProviderStateMixin {
  late final tab = TabController(length: 2, vsync: this);
  final q = TextEditingController();
  List list = [], moves = [];
  bool lowOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = lowOnly ? await Api.i.get('/api/stock/low') : await Api.i.get('/api/products?q=${Uri.encodeQueryComponent(q.text)}');
        final m = await Api.i.get('/api/stock/moves');
        if (mounted) setState(() { list = r; moves = m; });
      });

  Future<void> _adjust(Map p) async {
    final d = TextEditingController();
    final memo = TextEditingController();
    String reason = '입고';
    Map unit = baseUnitOf(p) ?? {'Qty': 1, 'Id': 0};
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('${p['Name']}  (현재 ${stockText(p)})'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: '입고', label: Text('입고 +')), ButtonSegment(value: '출고', label: Text('출고/폐기 −')), ButtonSegment(value: '실사', label: Text('실사(수량 맞춤)'))],
              selected: {reason},
              onSelectionChanged: (s) => set(() => reason = s.first),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final u in unitsOf(p))
                ChoiceChip(label: Text(unitLabel(u)), selected: asInt(u['Id']) == asInt(unit['Id']), onSelected: (_) => set(() => unit = u)),
            ]),
            field(d, reason == '실사' ? '실제 수량 (선택한 단위 기준)' : '수량 (선택한 단위 기준)', number: true),
            field(memo, '메모'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('저장'))],
        ),
      ),
    );
    if (ok != true) return;
    final n = (int.tryParse(d.text) ?? 0) * (asInt(unit['Qty']) < 1 ? 1 : asInt(unit['Qty']));
    final delta = reason == '입고' ? n : reason == '출고' ? -n : n - asInt(p['Stock']);
    if (delta == 0) return;
    await guard(context, () async {
      await Api.i.post('/api/stock/adjust', {'productId': p['Id'], 'delta': delta, 'reason': reason, 'memo': memo.text});
      await _load();
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TabBar(controller: tab, tabs: const [Tab(text: '재고 현황'), Tab(text: '입출고 내역')]),
        Expanded(
          child: TabBarView(controller: tab, children: [
            Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(child: TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: '상품 검색 (바코드 스캔 가능)', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true))),
                  if (isMobile) IconButton(onPressed: () async { final v = await scanBarcode(context); if (v != null) { q.text = v; _load(); } }, icon: const Icon(Icons.camera_alt)),
                  FilterChip(label: const Text('부족만'), selected: lowOnly, onSelected: (v) { lowOnly = v; _load(); }),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = list[i];
                    final low = asInt(p['MinStock']) > 0 && asInt(p['Stock']) <= asInt(p['MinStock']);
                    return ListTile(
                      dense: true,
                      title: Text('${p['Name']}${'${p['Spec'] ?? ''}'.isEmpty ? '' : '  ${p['Spec']}'}'),
                      subtitle: Text('${p['Barcode']}  최소 ${p['MinStock']}'),
                      trailing: Text(stockText(p), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: low ? Colors.red : null)),
                      onTap: () => _adjust(p),
                    );
                  },
                ),
              ),
            ]),
            ListView.separated(
              itemCount: moves.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = moves[i];
                final dl = asInt(m['Delta']);
                return ListTile(
                  dense: true,
                  title: Text('${m['Name'] ?? ''}'),
                  subtitle: Text('${m['MoveDate']}  ${m['Reason']}  ${m['UserName'] ?? ''}  ${m['Memo'] ?? ''}'),
                  trailing: Text(dl > 0 ? '+$dl' : '$dl', style: TextStyle(fontWeight: FontWeight.bold, color: dl > 0 ? Colors.green : Colors.red)),
                );
              },
            ),
          ]),
        ),
      ]);
}
