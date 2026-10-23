// 页面骨架：宽屏时右侧固定参数栏，窄屏（手机）时参数在上、图表在下。
import 'package:flutter/material.dart';

class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.controls,
    required this.body,
    this.controlsWidth = 392,
    this.breakpoint = 1020,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  final Widget controls;
  final Widget body;
  final double controlsWidth;
  final double breakpoint;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= breakpoint;
        if (!wide) {
          return ListView(
            padding: padding,
            children: [
              controls,
              const SizedBox(height: 16),
              body,
            ],
          );
        }
        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 16, bottom: 24),
                  child: body,
                ),
              ),
              SizedBox(
                width: controlsWidth,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: controls,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
