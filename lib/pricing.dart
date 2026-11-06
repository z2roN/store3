import 'dart:math';
import 'api.dart';

/// 상품(Map)의 단위 목록. 서버가 Units 로 내려준다.
List<Map> unitsOf(Map p) => ((p['Units'] as List?) ?? const []).map((e) => e as Map).toList();

Map? baseUnitOf(Map p) {
  final us = unitsOf(p);
  if (us.isEmpty) return null;
  return us.firstWhere((u) => u['IsBase'] == true, orElse: () => us.first);
}

int tierPrice(Map u, int tier) => asInt(u['Price$tier']);

/// 단위·판매가 등급별 판매 단가.
/// 순서: 그 단위의 해당 등급 가격 → (2차 단위면) 낱개 해당 등급 가격×입수 → 그 단위의 1번 가격 → 낱개 1번×입수 → 소비자가
int unitPrice(Map p, Map u, int tier) {
  final base = baseUnitOf(p) ?? u;
  final q = max(1, asInt(u['Qty']));
  final isBase = asInt(u['Id']) == asInt(base['Id']);
  tier = tier.clamp(1, 10);
  var v = tierPrice(u, tier);
  if (v > 0) return v;
  if (!isBase) {
    v = tierPrice(base, tier);
    if (v > 0) return v * q;
  }
  v = tierPrice(u, 1);
  if (v > 0) return v;
  if (!isBase) {
    v = tierPrice(base, 1);
    if (v > 0) return v * q;
  }
  v = asInt(u['Retail']);
  if (v > 0) return v;
  return asInt(base['Retail']) * q;
}

/// 재고(낱개)를 "박스 2 + 갑 3 + 개 5" 형태로 풀어서 표시
String stockText(Map p) {
  final s = asInt(p['Stock']);
  final base = baseUnitOf(p);
  final bn = '${base?['UnitName'] ?? p['BaseUnit'] ?? '개'}';
  final us = unitsOf(p).where((u) => asInt(u['Qty']) > 1).toList()..sort((a, b) => asInt(b['Qty']).compareTo(asInt(a['Qty'])));
  if (s <= 0 || us.isEmpty) return '$s$bn';
  var rest = s;
  final used = <int>{};
  final parts = <String>[];
  for (final u in us) {
    final q = asInt(u['Qty']);
    if (!used.add(q)) continue;
    if (rest >= q) {
      parts.add('${u['UnitName']} ${rest ~/ q}');
      rest %= q;
    }
  }
  if (rest > 0) parts.add('$bn $rest');
  return '$s$bn (${parts.join(' + ')})';
}

String unitLabel(Map u) => asInt(u['Qty']) > 1 ? '${u['UnitName']} (${u['Qty']}입)' : '${u['UnitName']}';
