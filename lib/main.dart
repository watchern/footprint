import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/app_nav.dart';
import 'core/db.dart';
import 'core/location_provider.dart';
import 'core/map_settings.dart';
import 'core/tracker.dart';
import 'pages/history_page.dart';
import 'pages/map_page.dart';
import 'pages/profile_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 intl 中文日期数据（DateFormat 使用 zh_CN 等非默认 locale 时必须先初始化）
  try {
    await initializeDateFormatting('zh_CN');
  } catch (_) {
    // 忽略：应用内的日期格式化已改为不依赖 locale 的实现
  }
  await AppDb.localId(); // 首次启动自动生成本地账号
  runApp(const LocalFootprintsApp());
}

class LocalFootprintsApp extends StatelessWidget {
  const LocalFootprintsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => Tracker()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => MapSettings()..load()),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: MaterialApp(
        title: '本地足迹',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F6E56)),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  Widget build(BuildContext context) {
    final nav = context.watch<AppNav>();
    return Scaffold(
      body: IndexedStack(
        index: nav.index,
        children: const [MapPage(), HistoryPage(), ProfilePage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: nav.index,
        onDestinationSelected: nav.goTo,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '轨迹'),
          NavigationDestination(icon: Icon(Icons.timeline_outlined), selectedIcon: Icon(Icons.timeline), label: '时间轴'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
