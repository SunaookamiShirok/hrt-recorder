// 应用外壳：暗紫主题 + 底部五个 tab。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme_controller.dart';
import '../data/settings_repository.dart';
import 'pages/calibration_page.dart';
import 'pages/overview_page.dart';
import 'pages/profile_page.dart';
import 'pages/records_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'unit_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsRepository.instance.load();
  runApp(const PkSimApp());
}

class PkSimApp extends StatelessWidget {
  const PkSimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([ThemeController.instance, UnitController.instance]),
      builder: (context, _) {
        final accent = ThemeController.instance.accent;
        PkTheme.accent = accent;
        return UnitScope(
          unit: UnitController.instance.value,
          child: MaterialApp(
            title: 'HRT Recorder',
            debugShowCheckedModeBanner: false,
            theme: ThemeController.instance.theme(),
            darkTheme: ThemeController.instance.theme(),
            themeMode: ThemeMode.dark,
            locale: const Locale('zh', 'CN'),
            supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const HomeShell(),
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    OverviewPage(),
    RecordsPage(),
    CalibrationPage(),
    SettingsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PkTheme.surface,
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: accent.withValues(alpha: 0.22),
          selectedIndex: _index,
          height: 62,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart, color: accent),
              label: '概览',
            ),
            NavigationDestination(
              icon: const Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note, color: accent),
              label: '记录',
            ),
            NavigationDestination(
              icon: const Icon(Icons.science_outlined),
              selectedIcon: Icon(Icons.science, color: accent),
              label: '校准',
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings, color: accent),
              label: '设置',
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: accent),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
