import 'package:flutter_test/flutter_test.dart';
import 'package:pk_sim/core/fitting.dart';
import 'package:pk_sim/core/pk.dart';
import 'package:pk_sim/utils/units.dart';

void main() {
  group('浓度单位换算', () {
    test('1 mg/L = 1000 ng/mL = 1e6 pg/mL', () {
      expect(ConcentrationUnit.mgPerL.convert(0.001), closeTo(0.001, 1e-15));
      expect(ConcentrationUnit.ngPerMl.convert(0.001), closeTo(1, 1e-12));
      expect(ConcentrationUnit.pgPerMl.convert(0.001), closeTo(1000, 1e-9));
    });

    test('反复换算保持一致', () {
      for (final u in ConcentrationUnit.values) {
        expect(u.toBase(u.convert(0.0123)), closeTo(0.0123, 1e-15));
      }
    });

    test('单位标签', () {
      expect(ConcentrationUnit.pgPerMl.label, 'pg/mL');
      expect(ConcentrationUnit.ngPerMl.aucLabel, 'ng·h/mL');
    });
  });

  group('储库 / flip-flop 拟合', () {
    // 肌注储库型：吸收（释放）远慢于消除，ka < k。
    const truth = PkParams(
      model: PkModel.oneCompOral,
      dose: 5,
      vd: 600,
      k: 0.09,
      ka: 0.004,
      f: 1.0,
    );
    final profile = PkProfile(truth);
    final points = [
      for (final t in <double>[2, 6, 12, 24, 48, 72, 96, 120, 168])
        ObservedPoint(t, profile.concentration(t)),
    ];

    test('给定消除常数时能还原释放速率 ka < k', () {
      final result = PkFitter(points: points, dose: 5)
          .fitOral(allowFlipFlop: true, fixedK: 0.09);
      expect(result.params.ka, lessThan(result.params.k));
      expect(result.r2, greaterThan(0.99));
      expect(result.params.ka, closeTo(0.004, 0.002));
    });

    test('普通口服模式会把 ka/k 交换成 ka > k', () {
      final result = PkFitter(points: points, dose: 5).fitOral();
      expect(result.params.ka, greaterThanOrEqualTo(result.params.k));
    });

    test('flip-flop 曲线的达峰时间明显晚于普通口服', () {
      final depotPeak = PkSimulator(const PkScenario(params: truth)).singleDoseMetrics(400).tMax;
      const fast = PkParams(model: PkModel.oneCompOral, dose: 5, vd: 600, k: 0.09, ka: 1.5, f: 1);
      final fastPeak = PkSimulator(const PkScenario(params: fast)).singleDoseMetrics(48).tMax;
      expect(depotPeak, greaterThan(24));
      expect(fastPeak, lessThan(5));
      expect(depotPeak, greaterThan(fastPeak * 5));
    });
  });

  group('双吸收相（含服/复方）', () {
    const truth = PkParams(
      model: PkModel.dualAbsorption,
      dose: 2,
      vd: 700,
      k: 0.0693,
      ka: 5.0,
      ka2: 0.9,
      f: 0.15,
      fFast: 0.55,
    );
    final profile = PkProfile(truth);

    test('C(0) = 0 且曲线先升后降', () {
      expect(profile.concentration(0), 0);
      expect(profile.concentration(0.5), greaterThan(0));
      // 慢相把峰值往后推，24 h 时已明显回落
      expect(profile.concentration(24), lessThan(profile.concentration(0.5)));
    });

    test('AUC 与两相如何分配无关，只等于 F·D/CL', () {
      final m = PkSimulator(const PkScenario(params: truth)).singleDoseMetrics(600);
      final expected = 0.15 * 2 / (0.0693 * 700);
      expect(m.aucInf, closeTo(expected, expected * 0.01));
    });

    test('F1 = 1 时退化为单相口服', () {
      const dual = PkParams(
        model: PkModel.dualAbsorption,
        dose: 100,
        vd: 40,
        k: 0.1,
        ka: 2.0,
        ka2: 0.8,
        f: 0.6,
        fFast: 1.0,
      );
      const single = PkParams(
        model: PkModel.oneCompOral,
        dose: 100,
        vd: 40,
        k: 0.1,
        ka: 2.0,
        f: 0.6,
      );
      final a = PkProfile(dual);
      final b = PkProfile(single);
      for (final t in <double>[0.5, 2, 6, 12]) {
        expect(a.concentration(t), closeTo(b.concentration(t), 1e-9));
      }
    });

    test('固定 k 与快相 ka1 后能还原慢相与占比', () {
      final points = [
        for (final t in <double>[0.25, 0.5, 1, 1.5, 2, 3, 4, 6, 8, 12, 24])
          ObservedPoint(t, profile.concentration(t)),
      ];
      final result = PkFitter(points: points, dose: 2).fitDual(fixedK: 0.0693, fastKa: 5.0);
      expect(result.r2, greaterThan(0.999));
      expect(result.params.ka2, closeTo(0.9, 0.15));
      expect(result.params.fFast, closeTo(0.55, 0.08));
    });
  });

  test('零级输入的 AUC 等于 D/CL，与输入时长无关', () {
    const expected = 0.35 / (0.0866 * 600);
    for (final t in <double>[2, 6, 24, 48, 84]) {
      final params = PkParams(
        model: PkModel.zeroOrder,
        dose: 0.35,
        infusionDuration: t,
        vd: 600,
        k: 0.0866,
      );
      final m = PkSimulator(PkScenario(params: params)).singleDoseMetrics(600);
      expect(m.aucInf, closeTo(expected, expected * 0.02), reason: 'T=$t 时 AUC 应等于 D/CL');
    }
  });
}
