import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';

/// 서버 주소(내부/외부) 설정 + 로그인
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final inC = TextEditingController(text: Api.i.internalAddr);
  final exC = TextEditingController(text: Api.i.externalAddr);
  final userC = TextEditingController(text: Api.i.loginName);
  final pinC = TextEditingController();
  bool busy = false;
  String? err;

  Future<void> _login() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await Api.i.saveAddrs(inC.text, exC.text);
      await Api.i.login(userC.text.trim(), pinC.text);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('z2roN-Store', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              Text('v$kAppVersion', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: inC,
                decoration: const InputDecoration(
                    labelText: '서버 주소 (매장 내부)', hintText: '예) 192.168.0.10:5080', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: exC,
                decoration: const InputDecoration(
                    labelText: '서버 주소 (외부, 선택)',
                    hintText: '예) store.example.com:5080 또는 VPN 주소',
                    helperText: '내부 주소가 안 될 때 자동으로 외부 주소를 사용합니다',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(controller: userC, decoration: const InputDecoration(labelText: '아이디', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              TextField(
                controller: pinC,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(labelText: '비밀번호', border: OutlineInputBorder()),
              ),
              if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 16),
              FilledButton(onPressed: busy ? null : _login, child: Text(busy ? '연결 중...' : '로그인')),
              const SizedBox(height: 8),
              const Text('처음 설치 시 아이디 admin / 비밀번호 1234 (로그인 후 꼭 변경하세요)',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        ),
      ),
    );
  }
}
