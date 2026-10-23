import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pk_sim/ui/app.dart';

void main() {
  testWidgets('启动后显示概览与底部导航', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PkSimApp());
    await tester.pumpAndSettle();

    expect(find.text('当前估算血药浓度'), findsOneWidget);
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('记录'), findsWidgets);
    expect(find.text('校准'), findsOneWidget);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });

  testWidgets('切换到记录页显示用药与化验', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PkSimApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('记录').first);
    await tester.pumpAndSettle();

    expect(find.text('用药'), findsOneWidget);
    expect(find.text('化验'), findsOneWidget);
  });

  testWidgets('切换到校准页显示四个子页', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const PkSimApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('校准'));
    await tester.pumpAndSettle();

    expect(find.text('单次'), findsOneWidget);
    expect(find.text('多次'), findsOneWidget);
    expect(find.text('拟合'), findsOneWidget);
    expect(find.text('ML'), findsOneWidget);
  });
}
