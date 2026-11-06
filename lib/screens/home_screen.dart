import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart';
import 'common.dart';
import 'customers_screen.dart';
import 'history_screen.dart';
import 'products_screen.dart';
import 'sale_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int idx = 0;
  static const tabs = [
    (Icons.point_of_sale, '판매'),
    (Icons.inventory_2, '상품'),
    (Icons.warehouse, '재고'),
    (Icons.people, '고객'),
    (Icons.receipt_long, '내역'),
    (Icons.settings, '설정'),
  ];

  Widget _page(int i) {
    switch (i) {
      case 0:
        return const SaleScreen();
      case 1:
        return const ProductsScreen();
      case 2:
        return const StockScreen();
      case 3:
        return const CustomersScreen();
      case 4:
        return const HistoryScreen();
      default:
        return const SettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    final api = Api.i;
    final title = Text('z2roN-Store v$kAppVersion   ${api.userName}${api.onExternal ? '  (외부 접속)' : ''}', style: const TextStyle(fontSize: 15));
    final body = KeyedSubtree(key: ValueKey(idx), child: _page(idx));
    if (wide) {
      return Scaffold(
        appBar: AppBar(title: title, actions: [TextButton(onPressed: api.logout, child: const Text('로그아웃'))]),
        body: Row(children: [
          NavigationRail(
            selectedIndex: idx,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => idx = i),
            destinations: [for (final t in tabs) NavigationRailDestination(icon: Icon(t.$1), label: Text(t.$2))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: title, actions: [IconButton(onPressed: api.logout, icon: const Icon(Icons.logout))]),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.$1), label: t.$2)],
      ),
    );
  }
}
