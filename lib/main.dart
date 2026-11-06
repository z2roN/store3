import 'package:flutter/material.dart';
import 'api.dart';
import 'screens/connect_screen.dart';
import 'screens/home_screen.dart';

const kAppVersion = '0.2.0';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.i.load();
  runApp(const StoreApp());
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'z2roN-Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2F6F5E), useMaterial3: true),
      home: ListenableBuilder(
        listenable: Api.i,
        builder: (_, __) => Api.i.loggedIn ? const HomeScreen() : const ConnectScreen(),
      ),
    );
  }
}
