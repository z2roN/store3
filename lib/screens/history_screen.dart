import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api.dart';
import '../receipt.dart';
import 'common.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime from = DateTime.now(), to = DateTime.now();
  List sales = [];
  List byMethod = [];
  final f = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final r = await Api.i.get('/api/sales?from=${f.format(from)}&to=${f.format(to)}');
        if (mounted) setState(() => sales = r);
      });

  Future<void> _pickDate(bool isFrom) async {
    final d = await showDatePicker(context: context, initialDate: isFrom ? from : to, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      if (isFrom) {
        from = d;
        if (to.isBefore(d)) to = d;
      } else {
        to = d;
        if (from.isAfter(d)) from = d;
      }
    });
    _load();
  }

  Future<void> _detail(Map s) async {
    await guard(context, () async {
      final d = await Api.i.get('/api/sales/${s['Id']}');
      final st = Map<String, dynamic>.from(await Api.i.get('/api/settings'));
      if (!mounted) return;
      final sale = d['sale'] as Map;
      final items = d['items'] as List;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${sale['SaleNo']}${sale['Cancelled'] == true ? '  (취소됨)' : ''}'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${sale['SaleDate']}  ${sale['UserName'] ?? ''}  ${sale['CustomerName'] ?? ''}'),
              const Divider(),
              for (final i in items) ListTile(dense: true, title: Text('${i['Name']}${asInt(i['UnitQty']) > 1 ? '  [${i['UnitName']} ×${i['UnitQty']}]' : ''}'), subtitle: Text('${won(asInt(i['Price']))} x ${i['Qty']}'), trailing: Text(won(asInt(i['Amount'])))),
              const Divider(),
              Text('합계 ${won(asInt(sale['Total']))}  (${sale['PayMethod']}, 결제 ${won(asInt(sale['Paid']))})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
          ),
          actions: [
            if (sale['Cancelled'] != true)
              TextButton(
                onPressed: () async {
                  if (await confirm(ctx, '이 판매를 취소할까요? (재고가 복구됩니다)')) {
                    await guard(ctx, () async {
                      await Api.i.post('/api/sales/${sale['Id']}/cancel');
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    });
                  }
                },
                child: const Text('판매 취소', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
            FilledButton(onPressed: () => guard(ctx, () => printReceipt(sale, items, st)), child: const Text('영수증 출력')),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final live = sales.where((s) => s['Cancelled'] != true);
    final total = live.fold<int>(0, (a, s) => a + asInt(s['Total']));
    final paid = live.fold<int>(0, (a, s) => a + asInt(s['Paid']));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton(onPressed: () => _pickDate(true), child: Text(f.format(from))),
          const Text('~'),
          OutlinedButton(onPressed: () => _pickDate(false), child: Text(f.format(to))),
          TextButton(onPressed: () { setState(() { from = to = DateTime.now(); }); _load(); }, child: const Text('오늘')),
          TextButton(onPressed: () { final n = DateTime.now(); setState(() { from = DateTime(n.year, n.month, 1); to = n; }); _load(); }, child: const Text('이번 달')),
        ]),
      ),
      Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(10),
        child: Text('${live.length}건   매출 ${won(total)}   수금 ${won(paid)}   외상 ${won(total - paid)}', style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      Expanded(
        child: ListView.separated(
          itemCount: sales.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = sales[i];
            final cx = s['Cancelled'] == true;
            return ListTile(
              dense: true,
              title: Text('${s['SaleNo']}  ${s['CustomerName'] ?? ''}', style: TextStyle(decoration: cx ? TextDecoration.lineThrough : null)),
              subtitle: Text('${s['SaleDate']}  ${s['PayMethod']}  ${s['UserName'] ?? ''}'),
              trailing: Text(won(asInt(s['Total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => _detail(s),
            );
          },
        ),
      ),
    ]);
  }
}
