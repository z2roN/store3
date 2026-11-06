import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 모바일 카메라 바코드 스캔 (한 번 읽으면 값을 돌려주고 닫힘)
Future<String?> scanBarcode(BuildContext context) {
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool done = false;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('바코드 스캔')),
      body: MobileScanner(onDetect: (cap) {
        if (done) return;
        final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
        if (v != null) {
          done = true;
          Navigator.of(context).pop(v);
        }
      }),
    );
  }
}
