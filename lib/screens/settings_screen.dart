import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api.dart';
import '../main.dart';
import 'common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final inC = TextEditingController(text: Api.i.internalAddr);
  final exC = TextEditingController(text: Api.i.externalAddr);
  final store = TextEditingController(), biz = TextEditingController(), addr = TextEditingController(), phone = TextEditingController(), foot = TextEditingController();
  List users = [];
  final tierC = List.generate(10, (_) => TextEditingController());
  bool scanUnit = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guard(context, () async {
        final s = await Api.i.get('/api/settings') as Map;
        store.text = s['storeName'] ?? '';
        biz.text = s['bizNo'] ?? '';
        addr.text = s['address'] ?? '';
        phone.text = s['phone'] ?? '';
        foot.text = s['receiptFooter'] ?? '';
        await Api.i.loadConfig();
        for (var i = 0; i < 10; i++) {
          tierC[i].text = Api.i.tierNames[i];
        }
        scanUnit = Api.i.scanMode != 'base';
        if (Api.i.isAdmin) users = await Api.i.get('/api/users');
        if (mounted) setState(() {});
      });

  Future<void> _import() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xls', 'xlsx', 'csv'], withData: true);
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      if (mounted) toast(context, '파일을 읽을 수 없습니다');
      return;
    }
    if (!mounted) return;
    await guard(context, () async {
      await Api.i.postBytes('/api/products/import?name=${Uri.encodeQueryComponent(f.name)}', bytes);
      if (!mounted) return;
      await showDialog(context: context, barrierDismissible: false, builder: (_) => const _ImportProgress());
    });
  }

  Future<void> _userDialog([Map? u]) async {
    final ln = TextEditingController(text: '${u?['LoginName'] ?? ''}');
    final dn = TextEditingController(text: '${u?['DisplayName'] ?? ''}');
    final pin = TextEditingController();
    String role = '${u?['Role'] ?? 'staff'}';
    bool active = u?['Active'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(u == null ? '직원 추가' : '직원 수정'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (u == null) field(ln, '아이디'),
            field(dn, '이름'),
            field(pin, u == null ? '비밀번호' : '새 비밀번호 (바꿀 때만)'),
            DropdownButton<String>(value: role, items: const [DropdownMenuItem(value: 'staff', child: Text('직원')), DropdownMenuItem(value: 'admin', child: Text('관리자'))], onChanged: (v) => set(() => role = v!)),
            if (u != null) SwitchListTile(title: const Text('사용'), value: active, onChanged: (v) => set(() => active = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
            FilledButton(
              onPressed: () => guard(ctx, () async {
                await Api.i.post('/api/users', {'id': u?['Id'] ?? 0, 'loginName': ln.text.trim(), 'pin': pin.text, 'displayName': dn.text.trim(), 'role': role, 'active': active});
                if (ctx.mounted) Navigator.pop(ctx, true);
              }),
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('서버 연결', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        field(inC, '서버 주소 (매장 내부) 예) 192.168.0.10:5080'),
        field(exC, '서버 주소 (외부, 선택)'),
        Row(children: [
          FilledButton(
            onPressed: () => guard(context, () async {
              await Api.i.saveAddrs(inC.text, exC.text);
              final r = await Api.i.connect();
              if (mounted) toast(context, '연결됨: ${r['store']} (${Api.i.onExternal ? '외부' : '내부'} 주소)');
            }),
            child: const Text('저장 후 연결 확인'),
          ),
          const SizedBox(width: 12),
          Text('현재: ${Api.i.activeAddr.isEmpty ? '-' : Api.i.activeAddr}'),
        ]),
        const Divider(height: 32),
        Text('매장 정보 (영수증에 인쇄)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        field(store, '상호'),
        field(biz, '사업자번호'),
        field(addr, '주소'),
        field(phone, '전화번호'),
        field(foot, '영수증 하단 문구'),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: Api.i.isAdmin
                ? () => guard(context, () async {
                      await Api.i.post('/api/settings', {
                        'storeName': store.text, 'bizNo': biz.text, 'address': addr.text, 'phone': phone.text, 'receiptFooter': foot.text,
                        'scanUnitMode': scanUnit ? 'unit' : 'base',
                        for (var i = 0; i < 10; i++) 'tierName${i + 1}': tierC[i].text.trim(),
                      });
                      await Api.i.loadConfig();
                      if (mounted) toast(context, '저장되었습니다');
                    })
                : null,
            child: Text(Api.i.isAdmin ? '매장 정보 저장' : '매장 정보 저장 (관리자만)'),
          ),
        ),
        const Divider(height: 32),
        Text('판매 설정 (관리자만 저장)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('갑/박스 바코드를 스캔하면 그 단위로 판매'),
          subtitle: const Text('끄면 어떤 바코드를 스캔해도 낱개 1개로 담기고, 판매 줄을 눌러 단위를 바꿉니다'),
          value: scanUnit,
          onChanged: (v) => setState(() => scanUnit = v),
        ),
        const SizedBox(height: 6),
        const Text('판매가 등급 이름 (고객에게 적용할 가격 이름)'),
        const SizedBox(height: 6),
        Wrap(spacing: 10, children: [for (var i = 0; i < 10; i++) SizedBox(width: 200, child: field(tierC[i], '판매가 ${i + 1}'))]),
        const Text('※ 1번이 기본 매장 판매가입니다. 고객 정보에서 적용할 번호를 고르면 그 고객에게는 해당 가격으로 판매됩니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
        if (Api.i.isAdmin) ...[
          const Divider(height: 32),
          Text('상품 엑셀 가져오기', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('기존 프로그램에서 내보낸 상품 파일(.xls/.xlsx/.csv)을 선택하면 한 번에 등록합니다. 같은 묶음코드의 갑/타/박스는 2차 단위로 자동 연결됩니다. 이미 등록된 상품(기준코드)은 건너뜁니다. 가져오는 동안(수 분) 다른 작업이 느려질 수 있으니 영업 후에 하세요.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('상품 파일 선택해서 가져오기')),
          const Divider(height: 32),
          Row(children: [Text('직원 계정', style: Theme.of(context).textTheme.titleMedium), const Spacer(), TextButton.icon(onPressed: () => _userDialog(), icon: const Icon(Icons.add), label: const Text('추가'))]),
          for (final u in users) ListTile(dense: true, title: Text('${u['DisplayName']} (${u['LoginName']})'), subtitle: Text('${u['Role'] == 'admin' ? '관리자' : '직원'}${u['Active'] == false ? '  · 사용 안 함' : ''}'), onTap: () => _userDialog(u)),
        ],
        const Divider(height: 32),
        Text('z2roN-Store v$kAppVersion'),
      ]);
}

class _ImportProgress extends StatefulWidget {
  const _ImportProgress();
  @override
  State<_ImportProgress> createState() => _ImportProgressState();
}

class _ImportProgressState extends State<_ImportProgress> {
  Map st = {};
  bool stop = false;

  @override
  void initState() {
    super.initState();
    _poll();
  }

  @override
  void dispose() {
    stop = true;
    super.dispose();
  }

  Future<void> _poll() async {
    while (!stop) {
      try {
        final r = await Api.i.get('/api/products/import/status');
        if (!mounted) return;
        setState(() => st = r);
        if (r['running'] != true && '${r['message']}' != '파일 읽는 중...') return;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = asInt(st['total']), done = asInt(st['done']);
    final finished = st.isNotEmpty && st['running'] != true;
    return AlertDialog(
      title: const Text('상품 가져오기'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${st['message'] ?? '시작하는 중...'}'),
        const SizedBox(height: 10),
        LinearProgressIndicator(value: total > 0 ? done / total : null),
        const SizedBox(height: 8),
        Text('$done / $total   등록 ${st['added'] ?? 0}  건너뜀 ${st['skipped'] ?? 0}'),
        if (asInt(st['dupBarcodes']) > 0) Text('중복 바코드 ${st['dupBarcodes']}개는 비워서 등록했습니다'),
        if (asInt(st['newVendors']) > 0) Text('새 업체 ${st['newVendors']}곳 자동 등록 (이름을 나중에 수정하세요)'),
        if ('${st['error'] ?? ''}'.isNotEmpty) Text('오류: ${st['error']}', style: const TextStyle(color: Colors.red)),
      ]),
      actions: [if (finished) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
    );
  }
}
