// 校准：把原有的四个模拟 / 拟合页面收进 TabBar。
import 'package:flutter/material.dart';

import '../theme.dart';
import 'fitting_page.dart';
import 'ml_page.dart';
import 'multi_dose_page.dart';
import 'single_dose_page.dart';

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text('校准与模拟',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  TabBar(
                    isScrollable: true,
                    dividerColor: Colors.transparent,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    labelColor: PkTheme.text,
                    unselectedLabelColor: PkTheme.muted,
                    tabs: [
                      Tab(text: '单次'),
                      Tab(text: '多次'),
                      Tab(text: '拟合'),
                      Tab(text: 'ML'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                SingleDosePage(),
                MultiDosePage(),
                FittingPage(),
                MlPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
