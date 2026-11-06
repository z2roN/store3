import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiError implements Exception {
  final String message;
  final int? status;
  ApiError(this.message, [this.status]);
  @override
  String toString() => message;
}

/// 서버(매장 PC)와 통신. 내부 주소를 먼저, 안 되면 외부 주소로 자동 전환한다.
class Api extends ChangeNotifier {
  static final Api i = Api._();
  Api._();

  String internalAddr = '';
  String externalAddr = '';
  String loginName = '';
  String token = '';
  String userName = '';
  String role = '';
  String activeAddr = '';
  bool get loggedIn => token.isNotEmpty;
  bool get isAdmin => role == 'admin';
  bool get onExternal => activeAddr.isNotEmpty && activeAddr == externalAddr && activeAddr != internalAddr;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    internalAddr = p.getString('internal') ?? '';
    externalAddr = p.getString('external') ?? '';
    loginName = p.getString('loginName') ?? '';
  }

  Future<void> saveAddrs(String internal, String external) async {
    internalAddr = internal.trim();
    externalAddr = external.trim();
    activeAddr = '';
    final p = await SharedPreferences.getInstance();
    await p.setString('internal', internalAddr);
    await p.setString('external', externalAddr);
    notifyListeners();
  }

  static String _url(String a, String path) {
    var s = a.trim();
    if (!s.startsWith('http')) s = 'http://$s';
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return '$s$path';
  }

  List<String> get _candidates {
    final l = <String>[];
    if (activeAddr.isNotEmpty) l.add(activeAddr);
    for (final a in [internalAddr, externalAddr]) {
      if (a.isNotEmpty && !l.contains(a)) l.add(a);
    }
    return l;
  }

  Future<http.Response> _send(String method, String addr, String path, Object? body, Duration timeout) {
    final u = Uri.parse(_url(addr, path));
    final h = {'Content-Type': 'application/json; charset=utf-8', if (token.isNotEmpty) 'X-Token': token};
    final b = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'POST':
        return http.post(u, headers: h, body: b).timeout(timeout);
      case 'DELETE':
        return http.delete(u, headers: h).timeout(timeout);
      default:
        return http.get(u, headers: h).timeout(timeout);
    }
  }

  /// 연결 가능한 주소 찾기. 서버 정보(ping)를 돌려준다.
  Future<Map<String, dynamic>> connect() async {
    if (_candidates.isEmpty) throw ApiError('서버 주소를 설정에서 입력하세요');
    Object? last;
    for (final a in [internalAddr, externalAddr].where((e) => e.isNotEmpty)) {
      try {
        final r = await _send('GET', a, '/api/ping', null, const Duration(seconds: 3));
        if (r.statusCode == 200) {
          activeAddr = a;
          notifyListeners();
          return jsonDecode(utf8.decode(r.bodyBytes));
        }
      } catch (e) {
        last = e;
      }
    }
    throw ApiError('서버에 연결할 수 없습니다. 주소와 서버 실행 여부를 확인하세요.\n($last)');
  }

  Future<dynamic> req(String method, String path, [Object? body]) async {
    Object? last;
    for (final a in _candidates) {
      try {
        final r = await _send(method, a, path, body, const Duration(seconds: 8));
        if (activeAddr != a) {
          activeAddr = a;
          notifyListeners();
        }
        final data = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
        if (r.statusCode == 401 && path != '/api/login') {
          token = '';
          notifyListeners();
          throw ApiError('로그인이 만료되었습니다. 다시 로그인하세요', 401);
        }
        if (r.statusCode >= 400) {
          throw ApiError((data is Map && data['error'] != null) ? '${data['error']}' : '오류 (${r.statusCode})', r.statusCode);
        }
        return data;
      } on ApiError {
        rethrow;
      } catch (e) {
        last = e; // 연결 실패 → 다음 주소 시도
      }
    }
    throw ApiError('서버와 통신할 수 없습니다 ($last)');
  }

  // ---- 매장 설정(판매가 등급 이름 등) ----
  List<String> tierNames = [for (var i = 1; i <= 10; i++) i == 1 ? '매장 판매가' : '판매가 $i'];
  String scanMode = 'unit'; // unit: 2차 바코드를 찍으면 그 단위로 / base: 항상 낱개로

  Future<void> loadConfig() async {
    try {
      final s = await get('/api/settings') as Map;
      for (var i = 1; i <= 10; i++) {
        final v = '${s['tierName$i'] ?? ''}'.trim();
        if (v.isNotEmpty) tierNames[i - 1] = v;
      }
      scanMode = '${s['scanUnitMode'] ?? 'unit'}';
    } catch (_) {}
  }

  /// 큰 파일 업로드 (상품 엑셀 가져오기)
  Future<dynamic> postBytes(String path, List<int> bytes) async {
    Object? last;
    for (final a in _candidates) {
      try {
        final r = await http
            .post(Uri.parse(_url(a, path)), headers: {'Content-Type': 'application/octet-stream', 'X-Token': token}, body: bytes)
            .timeout(const Duration(minutes: 5));
        final data = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
        if (r.statusCode >= 400) throw ApiError((data is Map && data['error'] != null) ? '${data['error']}' : '오류 (${r.statusCode})', r.statusCode);
        return data;
      } on ApiError {
        rethrow;
      } catch (e) {
        last = e;
      }
    }
    throw ApiError('서버와 통신할 수 없습니다 ($last)');
  }

  Future<dynamic> get(String p) => req('GET', p);
  Future<dynamic> post(String p, [Object? b]) => req('POST', p, b ?? {});
  Future<dynamic> del(String p) => req('DELETE', p);

  Future<void> login(String user, String pin) async {
    await connect();
    final r = await req('POST', '/api/login', {'user': user, 'pin': pin});
    token = r['token'];
    userName = r['name'];
    role = r['role'];
    loginName = user;
    final p = await SharedPreferences.getInstance();
    await p.setString('loginName', user);
    await loadConfig();
    notifyListeners();
  }

  void logout() {
    token = '';
    notifyListeners();
  }
}

String won(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}${b.toString()}원';
}

int asInt(dynamic v) => v == null ? 0 : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
