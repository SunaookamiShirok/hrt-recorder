// 我的：关于与免责声明。
import 'package:flutter/material.dart';

import '../theme.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Text('我的', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: PkTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [PkTheme.accent.withValues(alpha: 0.18), PkTheme.surface],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [PkTheme.accentLight, PkTheme.accent],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.bloodtype, color: Colors.white),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('HRT Recorder',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('v1.0 · Flutter / Dart',
                      style: TextStyle(fontSize: 11, color: PkTheme.muted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          context,
          '功能',
          const Text(
            '· 5 个方案：E2 口服 / CPA 口服 / E2 贴片 / E2 含服 / E2 肌注\n'
            '· 用药记录与化验记录的本地存储（不上传）\n'
            '· 概览：当前估算浓度、区间、双轴曲线\n'
            '· 个体校准：经验缩放 / OU-Kalman / EKF / 贝叶斯 MAP（实验）\n'
            '· 参数拟合与 GBDT 代理模型',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ),
        _card(
          context,
          '免责声明',
          const Text(
            '本软件仅用于个人记录与趋势参考，不构成诊疗或给药建议。'
            '模型参数来自文献量级估计，个体差异很大；化验结果的解读请结合医生意见。'
            '如出现不适请及时就医。',
            style: TextStyle(fontSize: 12, height: 1.6, color: PkTheme.muted),
          ),
        ),
        _card(
          context,
          '数据与隐私',
          const Text(
            '所有记录只保存在本机（Windows 用户目录 / Android 应用私有目录 / 浏览器 localStorage）。'
            '软件不发起任何网络请求上传数据。记录为明文 JSON，未额外加密。',
            style: TextStyle(fontSize: 12, height: 1.6, color: PkTheme.muted),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
