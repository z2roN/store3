import 'package:flutter/material.dart';
import '../api.dart';
import '../pricing.dart';
import 'common.dart';
import 'scan.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final q = TextEditingController();
  List list = [];
  bool loading = true, disc = false;
  int total = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await guard(context, () async {
      final r = await Api.i.get('/api/products?q=${Uri.encodeQueryComponent(q.text)}&disc=$disc');
      final c = await Api.i.get('/api/products/count');
      if (mounted) setState(() { list = r; total = asInt(c['total']); });
    });
    if (mounted) setState(() => loading = false);
  }

  Future<void> _edit([Map? p]) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ProductEditScreen(p)));
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('상품 등록')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(child: TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: '상품명 / 바코드 / 분류 / 품번 검색', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              FilterChip(label: const Text('단종 포함'), selected: disc, onSelected: (v) { disc = v; _load(); }),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(alignment: Alignment.centerLeft, child: Text('전체 $total개 중 ${list.length}개 표시 (검색어를 입력해 좁히세요)', style: const TextStyle(fontSize: 12, color: Colors.grey))),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final p = list[i] as Map;
                      final b = baseUnitOf(p);
                      final us = unitsOf(p).where((u) => asInt(u['Qty']) > 1).toList();
                      final low = asInt(p['MinStock']) > 0 && asInt(p['Stock']) <= asInt(p['MinStock']);
                      return ListTile(
                        dense: true,
                        title: Text('${p['Name']}${'${p['Spec'] ?? ''}'.isEmpty ? '' : '  ${p['Spec']}'}${p['Discontinued'] == true ? '  (단종)' : ''}'),
                        subtitle: Text('${b?['Barcode'] ?? ''}${us.isEmpty ? '' : '   + ${us.map((u) => unitLabel(u)).join(', ')}'}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(won(b == null ? 0 : tierPrice(b, 1)), style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('재고 ${stockText(p)}', style: TextStyle(color: low ? Colors.red : null, fontSize: 12)),
                        ]),
                        onTap: () => _edit(p),
                      );
                    },
                  ),
          ),
        ]),
      );
}

/// 한 단위(기준/갑/박스...) 입력 행
class _UnitRow {
  final name = TextEditingController();
  final qty = TextEditingController(text: '1');
  final barcode = TextEditingController();
  final cost = TextEditingController();
  final retail = TextEditingController();
  final prices = List.generate(10, (_) => TextEditingController());
  _UnitRow();
  _UnitRow.from(Map u) {
    name.text = '${u['UnitName'] ?? ''}';
    qty.text = '${asInt(u['Qty']) < 1 ? 1 : asInt(u['Qty'])}';
    barcode.text = '${u['Barcode'] ?? ''}';
    cost.text = asInt(u['Cost']) == 0 ? '' : '${asInt(u['Cost'])}';
    retail.text = asInt(u['Retail']) == 0 ? '' : '${asInt(u['Retail'])}';
    for (var i = 0; i < 10; i++) {
      final v = asInt(u['Price${i + 1}']);
      prices[i].text = v == 0 ? '' : '$v';
    }
  }
  Map toJson() => {
        'unitName': name.text.trim(),
        'qty': int.tryParse(qty.text) ?? 1,
        'barcode': barcode.text.trim(),
        'cost': int.tryParse(cost.text) ?? 0,
        'retail': int.tryParse(retail.text) ?? 0,
        'prices': [for (final c in prices) int.tryParse(c.text) ?? 0],
      };
}

class ProductEditScreen extends StatefulWidget {
  final Map? p;
  const ProductEditScreen(this.p, {super.key});
  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final c = <String, TextEditingController>{};
  final flags = <String, bool>{};
  final units = <_UnitRow>[];
  List vendors = [];
  int vendorId = 0;
  bool get isNew => widget.p == null;

  TextEditingController t(String k) => c.putIfAbsent(k, () => TextEditingController(text: '${widget.p?[k] ?? ''}'));

  @override
  void initState() {
    super.initState();
    for (final k in ['Name', 'ShareName', 'Spec', 'Category', 'Maker', 'Origin', 'ItemNo', 'ItemNo2', 'ItemNo3', 'ItemNo4', 'BookCode', 'Shelf', 'Location', 'Keywords', 'Memo']) {
      t(k);
    }
    c['MinStock'] = TextEditingController(text: '${asInt(widget.p?['MinStock'])}');
    c['Stock'] = TextEditingController(text: '0');
    c['CostDC'] = TextEditingController(text: asInt(widget.p?['CostDC']) == 0 ? '' : '${asInt(widget.p?['CostDC'])}');
    for (final k in ['NoPoint', 'TaxFree', 'Discontinued', 'NoReturn', 'NoDiscount']) {
      flags[k] = widget.p?[k] == true;
    }
    vendorId = asInt(widget.p?['VendorId']);
    if (isNew) {
      units.add(_UnitRow()..name.text = '개');
    } else {
      for (final u in unitsOf(widget.p!)) {
        units.add(_UnitRow.from(u));
      }
      if (units.isEmpty) units.add(_UnitRow()..name.text = '개');
    }
    _loadVendors();
  }

  Future<void> _loadVendors() async {
    try {
      final v = await Api.i.get('/api/vendors');
      if (mounted) setState(() => vendors = v);
    } catch (_) {}
  }

  Future<void> _save() => guard(context, () async {
        await Api.i.post('/api/products', {
          'id': widget.p?['Id'] ?? 0,
          for (final k in ['Name', 'ShareName', 'Spec', 'Category', 'Maker', 'Origin', 'ItemNo', 'ItemNo2', 'ItemNo3', 'ItemNo4', 'BookCode', 'Shelf', 'Location', 'Keywords', 'Memo'])
            _camel(k): c[k]!.text.trim(),
          'kind': asInt(widget.p?['Kind']),
          'vendorId': vendorId,
          'minStock': int.tryParse(c['MinStock']!.text) ?? 0,
          'stock': int.tryParse(c['Stock']!.text) ?? 0,
          'costDC': int.tryParse(c['CostDC']!.text) ?? 0,
          'noPoint': flags['NoPoint'], 'taxFree': flags['TaxFree'], 'discontinued': flags['Discontinued'], 'noReturn': flags['NoReturn'], 'noDiscount': flags['NoDiscount'],
          'units': [for (final u in units) u.toJson()],
        });
        if (mounted) Navigator.pop(context, true);
      });

  static String _camel(String k) => k[0].toLowerCase() + k.substring(1);

  Widget _sec(String s) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(s, style: Theme.of(context).textTheme.titleMedium));

  Widget _row(List<Widget> ch) => Padding(padding: const EdgeInsets.only(bottom: 0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var i = 0; i < ch.length; i++) ...[if (i > 0) const SizedBox(width: 8), Expanded(child: ch[i])]]));

  Widget _unitCard(int i) {
    final u = units[i];
    final base = i == 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(base ? '기준 단위 (낱개)' : '2차 단위 ${i}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (!base) IconButton(onPressed: () => setState(() => units.removeAt(i)), icon: const Icon(Icons.delete_outline)),
          ]),
          _row([field(u.name, base ? '단위 (개, 자루...)' : '단위 (갑, 박스...)'), if (!base) field(u.qty, '입수 (낱개 몇 개)', number: true)]),
          Row(children: [
            Expanded(child: field(u.barcode, base ? '기준 바코드' : '${u.name.text.isEmpty ? '2차' : u.name.text} 바코드')),
            if (isMobile) IconButton(onPressed: () async { final v = await scanBarcode(context); if (v != null) setState(() => u.barcode.text = v); }, icon: const Icon(Icons.camera_alt)),
          ]),
          _row([field(u.cost, '매입단가', number: true), field(u.retail, '소비자가', number: true)]),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('판매가 등급별 가격${base ? '' : '  (비우면 낱개 가격 × 입수)'}', style: const TextStyle(fontSize: 14)),
            children: [
              Wrap(spacing: 8, children: [
                for (var k = 0; k < 10; k++)
                  SizedBox(width: 170, child: field(u.prices[k], Api.i.tierNames[k], number: true)),
              ]),
            ],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(isNew ? '상품 등록' : '상품 수정'),
          actions: [
            if (!isNew)
              TextButton(
                onPressed: () async {
                  if (await confirm(context, '이 상품을 삭제(숨김)할까요?')) {
                    await guard(context, () async {
                      await Api.i.del('/api/products/${widget.p!['Id']}');
                      if (mounted) Navigator.pop(context, true);
                    });
                  }
                },
                child: const Text('삭제', style: TextStyle(color: Colors.red)),
              ),
            FilledButton(onPressed: _save, child: const Text('저장')),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(14), children: [
              _sec('기본 정보'),
              field(c['Name']!, '상품명'),
              _row([field(c['Spec']!, '규격'), field(c['Category']!, '분류')]),
              field(c['ShareName']!, '공유상품명'),
              _sec('단위 · 바코드 · 가격'),
              const Text('낱개(기준) 단위가 기본 판매 단위입니다. 갑/박스 등은 2차 단위로 추가하세요.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              for (var i = 0; i < units.length; i++) _unitCard(i),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => units.add(_UnitRow())), icon: const Icon(Icons.add), label: const Text('2차 단위(갑/박스) 추가'))),
              _sec('거래처 · 재고'),
              DropdownButtonFormField<int>(
                value: vendors.any((v) => asInt(v['Id']) == vendorId) ? vendorId : 0,
                decoration: const InputDecoration(labelText: '매입사', border: OutlineInputBorder(), isDense: true),
                items: [const DropdownMenuItem(value: 0, child: Text('(없음)')), for (final v in vendors) DropdownMenuItem(value: asInt(v['Id']), child: Text('${v['Name']}'))],
                onChanged: (v) => setState(() => vendorId = v ?? 0),
              ),
              const SizedBox(height: 10),
              _row([field(c['Maker']!, '제조사'), field(c['Origin']!, '원산지')]),
              _row([if (isNew) field(c['Stock']!, '처음 재고 (낱개 수량)', number: true), field(c['MinStock']!, '최소재고 (부족 알림)', number: true), field(c['CostDC']!, '매입DC', number: true)]),
              _sec('기타'),
              _row([field(c['ItemNo']!, '품번'), field(c['ItemNo2']!, '품번2')]),
              _row([field(c['ItemNo3']!, '품번3'), field(c['ItemNo4']!, '품번4')]),
              _row([field(c['BookCode']!, '책자코드'), field(c['Keywords']!, '키워드')]),
              _row([field(c['Shelf']!, '매대'), field(c['Location']!, '위치')]),
              field(c['Memo']!, '비고'),
              Wrap(spacing: 6, children: [
                for (final e in const {'TaxFree': '면세', 'Discontinued': '단종', 'NoPoint': '적립제외', 'NoDiscount': '할인제외', 'NoReturn': '반품불가'}.entries)
                  FilterChip(label: Text(e.value), selected: flags[e.key] == true, onSelected: (v) => setState(() => flags[e.key] = v)),
              ]),
              const SizedBox(height: 60),
            ]),
          ),
        ),
      );
}
