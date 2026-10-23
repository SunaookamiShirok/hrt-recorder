import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/pk.dart';

void main() {
  group('一室静注', () {
    const params = PkParams(model: PkModel.oneCompIv, dose: 500, vd: 35, k: 0.12);
    final profile = PkProfile(params);

    test('C(0) = D/V', () {
      expect(profile.concentration(1e-9), closeTo(500 / 35, 1e-6));
    });

    test('AUC0-∞ = D/CL', () {
      final sim = PkSimulator(PkScenario(params: params));
      final m = sim.singleDoseMetrics(240);
      expect(m.aucInf, closeTo(500 / (0.12 * 35), 0.05));
    });

    test('t½ = ln2/k', () {
      expect(profile.tHalf, closeTo(math.ln2 / 0.12, 1e-9));
    });

    test('浓度每过一个半衰期减半', () {
      final c0 = profile.concentration(1e-9);
      final c1 = profile.concentration(profile.tHalf);
      expect(c1, closeTo(c0 / 2, 1e-6));
    });

    test('CL 与 Vss', () {
      expect(profile.clearance, closeTo(4.2, 1e-9));
      expect(profile.vss, closeTo(35, 1e-9));
      expect(profile.mrt, closeTo(1 / 0.12, 1e-9));
    });
  });

  group('一室口服', () {
    const params = PkParams(
      model: PkModel.oneCompOral,
      dose: 400,
      vd: 50,
      k: 0.14,
      ka: 1.1,
      f: 0.8,
    );
    final profile = PkProfile(params);

    test('C(0) = 0', () {
      expect(profile.concentration(0), 0);
    });

    test('AUC0-∞ = F·D/CL', () {
      final sim = PkSimulator(PkScenario(params: params));
      final m = sim.singleDoseMetrics(120);
      expect(m.aucInf, closeTo(0.8 * 400 / (0.14 * 50), 0.05));
    });

    test('Tmax 落在合理区间', () {
      final sim = PkSimulator(PkScenario(params: params));
      final m = sim.singleDoseMetrics(48);
      expect(m.tMax, greaterThan(0.5));
      expect(m.tMax, lessThan(8));
      expect(m.cMax, greaterThan(0));
    });

    test('ka == k 时用极限形式且不产生 NaN', () {
      const eq = PkParams(model: PkModel.oneCompOral, dose: 100, vd: 20, k: 0.3, ka: 0.3);
      final c = PkProfile(eq).concentration(2);
      expect(c.isFinite, isTrue);
      expect(c, greaterThan(0));
    });
  });

  group('二室静注', () {
    const params = PkParams(
      model: PkModel.twoCompIv,
      dose: 600,
      vd: 12,
      k: 0.08,
      k12: 0.9,
      k21: 0.5,
    );
    final profile = PkProfile(params);

    test('C(0) = D/V1', () {
      expect(profile.concentration(1e-9), closeTo(600 / 12, 1e-3));
    });

    test('AUC0-∞ = D/(V1·k10)', () {
      final sim = PkSimulator(PkScenario(params: params));
      final m = sim.singleDoseMetrics(400);
      expect(m.aucInf, closeTo(600 / (12 * 0.08), 0.2));
    });

    test('α > β > 0', () {
      expect(profile.alpha, greaterThan(profile.beta));
      expect(profile.beta, greaterThan(0));
    });

    test('Vss = V1(1 + k12/k21)', () {
      expect(profile.vss, closeTo(12 * (1 + 0.9 / 0.5), 1e-9));
    });
  });

  group('多次给药', () {
    const params = PkParams(model: PkModel.oneCompIv, dose: 500, vd: 35, k: 0.12);
    final steadySim = PkSimulator(
      const PkScenario(params: params, interval: 12, steadyState: true),
    );
    final seriesSim = PkSimulator(
      const PkScenario(params: params, interval: 12, doseCount: 8),
    );

    test('稳态峰谷关系与蓄积比', () {
      final m = steadySim.multipleDoseMetrics();
      // 解析解：Css,max = C0/(1−e^(−kτ))
      final expectedPeak = (500 / 35) / (1 - math.exp(-0.12 * 12));
      expect(m.steady.cMax, closeTo(expectedPeak, 0.05));
      expect(m.accumulation, closeTo(1 / (1 - math.exp(-0.12 * 12)), 0.02));
      expect(m.steady.cMin, greaterThan(0));
      expect(m.steady.cMin, lessThan(m.steady.cMax));
    });

    test('稳态 AUCτ = D/CL', () {
      final m = steadySim.multipleDoseMetrics();
      expect(m.steady.auc, closeTo(500 / (0.12 * 35), 0.2));
    });

    test('有限次给药在末次后浓度趋近稳态', () {
      expect(
        seriesSim.concentrationAt(8 * 12 - 0.01),
        closeTo(steadySim.concentrationAt(12 - 0.01), 0.5),
      );
    });
  });

  group('恒速输入（零级）', () {
    const params = PkParams(
      model: PkModel.zeroOrder,
      dose: 100,
      infusionDuration: 10,
      vd: 40,
      k: 0.1,
    );
    final profile = PkProfile(params);
    const cl = 4.0; // 0.1 * 40
    const r0 = 10.0; // 100 / 10

    test('输入期间与结束后的解析值', () {
      final cAtEnd = r0 / cl * (1 - math.exp(-0.1 * 10));
      expect(profile.concentration(0), closeTo(0, 1e-12));
      expect(profile.concentration(5), closeTo(r0 / cl * (1 - math.exp(-0.5)), 1e-9));
      expect(profile.concentration(10), closeTo(cAtEnd, 1e-9));
      expect(profile.concentration(20), closeTo(cAtEnd * math.exp(-1.0), 1e-9));
    });

    test('AUC0-∞ = D/CL', () {
      final m = PkSimulator(const PkScenario(params: params)).singleDoseMetrics(300);
      expect(m.aucInf, closeTo(100 / cl, 0.02));
    });

    test('峰浓度出现在输入结束时', () {
      final m = PkSimulator(const PkScenario(params: params)).singleDoseMetrics(48);
      expect(m.tMax, closeTo(10, 0.05));
    });

    test('连续输注（τ = T）稳态浓度 = R0/CL', () {
      final sim = PkSimulator(const PkScenario(params: params, interval: 10, steadyState: true));
      expect(sim.concentrationAt(5), closeTo(r0 / cl, 0.01));
      expect(sim.concentrationAt(9.9), closeTo(r0 / cl, 0.02));
    });
  });

  test('参数校验能捕获非法值', () {
    expect(const PkParams(vd: -1).validate(), isNotEmpty);
    expect(const PkParams(model: PkModel.oneCompOral, f: 2).validate(), isNotEmpty);
    expect(
      const PkParams(model: PkModel.zeroOrder, infusionDuration: 0).validate(),
      isNotEmpty,
    );
    expect(const PkParams().validate(), isEmpty);
  });
}
