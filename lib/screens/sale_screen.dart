import 'package:flutter/material.dart';
import '../api.dart';
import '../pricing.dart';
import '../receipt.dart';
import 'common.dart';
import 'scan.dart';

class CartItem {
  Map product;
  Map unit;
  int qty;
  int price;
  bool manual; // 직접 바꾼 단가는 고객 등급이 바뀌어도 유지
  CartItem(this.product, this.unit, this.qty, this.price, [this.manual = false]);
  int get uq => asInt(unit['Qty']) < 1 ? 1 : asInt(unit['Qty']);
  int get amount => qty * price;
  int get need => qty * uq;
  int get stock => asInt(product['Stock']);
  int get productId => asInt(product['Id']);
  String get name => '${product['Name']}${'${product['Spec'] ?? ''}'.isEmpty ? '' : ' ${product['Spec']}'}';
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final cart = <CartItem>[];
  final codeC = TextEditingController();
  final codeF = FocusNode();
  final discC = TextEditingController();
  final paidC = TextEditingController();
  String method = '현금';
  Map? customer;
  bool busy = false;

  int get sum => cart.fold(0, (a, b) => a + b.amount);
  int get disc => int.tryParse(discC.text) ?? 0;
  int get total => (sum - disc).clamp(0, 1 << 31);

  int get tier => customer == null ? 1 : (asInt(customer!['PriceTier']) < 1 ? 1 : asInt(customer!['PriceTier']));

  void _add(Map p, [Map? unit]) {
    final u = unit ?? baseUnitOf(p);
    if (u == null) {
      toast(context, '단위가 없는 상품입니다');
      return;
    }
    final id = asInt(p['Id']);
    final uid = asInt(u['Id']);
    final ex = cart.where((c) => c.productId == id && asInt(c.unit['Id']) == uid);
    setState(() {
      if (ex.isNotEmpty) {
        ex.first.qty++;
      } else {
        cart.add(CartItem(p, u, 1, unitPrice(p, u, tier)));
      }
    });
  }

  void _reprice() {
    for (final c in cart) {
      if (!c.manual) c.price = unitPrice(c.product, c.unit, tier);
    }
  }

  Future<void> _lookup(String raw) async {
    final code = raw.trim();
    codeC.clear();
    if (code.isEmpty) {
      codeF.requestFocus();
      return;
    }
    await guard(context, () async {
      try {
        final p = await Api.i.get('/api/products/barcode/${Uri.encodeComponent(code)}') as Map;
        final scanId = asInt(p['ScanUnitId']);
        Map? u = baseUnitOf(p);
        if (Api.i.scanMode == 'unit') {
          for (final x in unitsOf(p)) {
            if (asInt(x['Id']) == scanId) u = x;
          }
        }
        _add(p, u);
      } on ApiError catch (e) {
        if (e.status == 404) {
          final list = await Api.i.get('/api/products?q=${Uri.encodeQueryComponent(code)}') as List;
          if (list.isEmpty) throw ApiError('"$code" 상품을 찾을 수 없습니다');
          if (list.length == 1) {
            _add(list.first as Map);
          } else {
            await _pick(code);
          }
        } else {
          rethrow;
        }
      }
    });
    codeF.requestFocus();
  }

  Future<void> _pick([String initial = '']) async {
    final p = await showDialog<Map>(context: context, builder: (_) => _ProductPicker(initial));
    if (p != null) _add(p);
    codeF.requestFocus();
  }

  Future<void> _pickCustomer() async {
    final c = await showDialog<Map>(context: context, builder: (_) => const _CustomerPicker());
    if (c != null) setState(() { customer = c['Id'] == -1 ? null : c; _reprice(); });
  }

  Future<void> _pay() async {
    if (cart.isEmpty) return;
    if (method == '외상' && customer == null) {
      toast(context, '외상 판매는 고객을 선택하세요');
      return;
    }
    setState(() => busy = true);
    await guard(context, () async {
      final paid = method == '외상' ? (int.tryParse(paidC.text) ?? 0) : total;
      final r = await Api.i.post('/api/sales', {
        'customerId': customer == null ? 0 : asInt(customer!['Id']),
        'items': [for (final c in cart) {'productId': c.productId, 'name': c.name, 'qty': c.qty, 'price': c.price, 'unitName': '${c.unit['UnitName']}', 'unitQty': c.uq}],
        'discount': disc,
        'paid': paid,
        'payMethod': method,
      });
      final d = await Api.i.get('/api/sales/${r['id']}');
      final st = Map<String, dynamic>.from(await Api.i.get('/api/settings'));
      setState(() {
        cart.clear();
        discC.clear();
        paidC.clear();
        customer = null;
        method = '현금';
      });
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('판매 완료'),
          content: Text('영수증 ${r['saleNo']}\n합계 ${won(asInt(r['total']))}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
            FilledButton(
              onPressed: () async {
                await guard(context, () => printReceipt(d['sale'], d['items'], st));
              },
              child: const Text('영수증 출력'),
            ),
          ],
        ),
      );
    });
    if (mounted) setState(() => busy = false);
    codeF.requestFocus();
  }

  Future<void> _editLine(CartItem c) async {
    final units = unitsOf(c.product);
    Map sel = c.unit;
    final pc = TextEditingController(text: '${c.price}');
    final qc = TextEditingController(text: '${c.qty}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(c.name),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('판매 단위'),
            Wrap(spacing: 6, children: [
              for (final u in units)
                ChoiceChip(
                  label: Text(unitLabel(u)),
                  selected: asInt(u['Id']) == asInt(sel['Id']),
                  onSelected: (_) => set(() {
                    sel = u;
                    pc.text = '${unitPrice(c.product, u, tier)}';
                  }),
                ),
            ]),
            const SizedBox(height: 12),
            field(qc, '수량', number: true),
            field(pc, '단가 (직접 수정 가능)', number: true),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('확인'))],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        c.unit = sel;
        c.qty = (int.tryParse(qc.text) ?? c.qty).clamp(1, 999999);
        final np = int.tryParse(pc.text) ?? c.price;
        c.manual = np != unitPrice(c.product, sel, tier);
        c.price = np;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: codeC,
              focusNode: codeF,
              autofocus: true,
              onSubmitted: _lookup,
              decoration: const InputDecoration(
                  labelText: '바코드 스캔 / 상품명 입력 후 Enter', prefixIcon: Icon(Icons.qr_code_scanner), border: OutlineInputBorder(), isDense: true),
            ),
          ),
          const SizedBox(width: 6),
          if (isMobile)
            IconButton.filledTonal(
                onPressed: () async {
                  final v = await scanBarcode(context);
                  if (v != null) _lookup(v);
                },
                icon: const Icon(Icons.camera_alt)),
          IconButton.filledTonal(onPressed: () => _pick(), icon: const Icon(Icons.search)),
        ]),
      ),
      Expanded(
        child: cart.isEmpty
            ? const Center(child: Text('바코드를 스캔하거나 상품을 검색해 추가하세요'))
            : ListView.separated(
                itemCount: cart.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final c = cart[i];
                  return ListTile(
                    dense: true,
                    title: Text('${c.name}  [${c.uq > 1 ? unitLabel(c.unit) : c.unit['UnitName']}]'),
                    subtitle: Text('${won(c.price)}${c.stock < c.need ? '   ⚠ 재고 ${c.stock}' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(onPressed: () => setState(() => c.qty > 1 ? c.qty-- : cart.removeAt(i)), icon: const Icon(Icons.remove_circle_outline)),
                      Text('${c.qty}', style: const TextStyle(fontSize: 16)),
                      IconButton(onPressed: () => setState(() => c.qty++), icon: const Icon(Icons.add_circle_outline)),
                      SizedBox(width: 90, child: Text(won(c.amount), textAlign: TextAlign.right)),
                      IconButton(onPressed: () => setState(() => cart.removeAt(i)), icon: const Icon(Icons.close)),
                    ]),
                    onTap: () => _editLine(c),
                  );
                },
              ),
      ),
    ]);

    final panel = Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('소계'), Text(won(sum))]),
          const SizedBox(height: 6),
          TextField(controller: discC, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: '할인 금액', isDense: true, border: OutlineInputBorder())),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('받을 금액', style: TextStyle(fontSize: 16)),
            Text(won(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: '현금', label: Text('현금')), ButtonSegment(value: '카드', label: Text('카드')), ButtonSegment(value: '외상', label: Text('외상'))],
            selected: {method},
            onSelectionChanged: (s) => setState(() => method = s.first),
          ),
          if (method == '외상')
            Padding(padding: const EdgeInsets.only(top: 8), child: TextField(controller: paidC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '지금 받은 금액 (나머지는 외상)', isDense: true, border: OutlineInputBorder()))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _pickCustomer, icon: const Icon(Icons.person), label: Text(customer == null ? '고객 선택 (선택사항)' : '${customer!['Name']}  ·  ${Api.i.tierNames[tier - 1]}')),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: busy || cart.isEmpty ? null : _pay,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(busy ? '처리 중...' : '결제 완료', style: const TextStyle(fontSize: 18)),
          ),
        ]),
      ),
    );

    if (MediaQuery.of(context).size.width >= 800) {
      return Row(children: [Expanded(child: list), SizedBox(width: 340, child: SingleChildScrollView(child: panel))]);
    }
    return Column(children: [Expanded(child: list), SingleChildScrollView(child: panel).let((w) => ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45), child: w))]);
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _ProductPicker extends StatefulWidget {
  final String initial;
  const _ProductPicker(this.initial);
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final q = TextEditingController(text: widget.initial);
  List list = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.i.get('/api/products?q=${Uri.encodeQueryComponent(q.text)}');
    if (mounted) setState(() => list = r);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('상품 검색'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            TextField(controller: q, autofocus: true, onChanged: (_) => _load(), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder())),
            Expanded(
              child: ListView(children: [
                for (final p in list) ListTile(dense: true, title: Text('${p['Name']}'), subtitle: Text('${p['Barcode']}  ${p['Spec'] ?? ''}  재고 ${stockText(p)}'), trailing: Text(won(asInt(p['Price']))), onTap: () => Navigator.pop(context, p)),
              ]),
            ),
          ]),
        ),
      );
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final q = TextEditingController();
  List list = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Api.i.get('/api/customers?q=${Uri.encodeQueryComponent(q.text)}');
    if (mounted) setState(() => list = r);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('고객 선택'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: Column(children: [
            TextField(controller: q, onChanged: (_) => _load(), decoration: const InputDecoration(hintText: '이름/전화번호', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder())),
            Expanded(
              child: ListView(children: [
                ListTile(dense: true, title: const Text('(선택 안 함)'), onTap: () => Navigator.pop(context, {'Id': -1})),
                for (final c in list) ListTile(dense: true, title: Text('${c['Name']}'), subtitle: Text('${c['Phone']}'), trailing: asInt(c['Balance']) != 0 ? Text('외상 ${won(asInt(c['Balance']))}') : null, onTap: () => Navigator.pop(context, c)),
              ]),
            ),
          ]),
        ),
      );
}
