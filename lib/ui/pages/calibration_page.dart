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
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 640;
                final title = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text('校准与模拟',
                      style: Theme.of(context).textTheme.headlineSmall),
                );
                final tabs = TabBar(
                  tabAlignment: narrow ? TabAlignment.start : TabAlignment.center,
                  isScrollable: true,
                  dividerColor: Colors.transparent,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: PkTheme.text,
                  unselectedLabelColor: PkTheme.muted,
                  tabs: const [
                    Tab(text: '单次'),
                    Tab(text: '多次'),
                    Tab(text: '拟合'),
                    Tab(text: 'ML'),
                  ],
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [title, tabs],
                  );
                }
                return Row(
                  children: [
                    title,
                    const SizedBox(width: 8),
                    tabs,
                  ],
                );
              },
            ),
          ),          const Expanded(
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
