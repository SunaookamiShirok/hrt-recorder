// 数据集工具：内置合成数据、CSV 导入、演示用实测数据。
import 'dart:math' as math;

import 'fitting.dart';
import 'pk.dart';

/// 一行训练样本：[x] 为特征向量，[y] 为（变换后的）标签。
class TrainingRow {
  const TrainingRow(this.x, this.y);

  final List<double> x;
  final double y;
}

/// 代理模型的特征定义。
class FeatureSpec {
  const FeatureSpec(this.name, this.unit);

  final String name;
  final String unit;
}

/// 血药浓度代理模型使用的 7 个特征。
const List<FeatureSpec> surrogateFeatures = [
  FeatureSpec('剂量', 'mg'),
  FeatureSpec('分布容积', 'L'),
  FeatureSpec('消除常数 k', 'h⁻¹'),
  FeatureSpec('吸收常数 ka', 'h⁻¹'),
  FeatureSpec('生物利用度 F', '—'),
  FeatureSpec('给药途径', '0静注/1口服'),
  FeatureSpec('时间 ln(t+0.5)', 'h'),
];

/// 时间特征的偏移量：ln(t + 0.5) 让指数衰减段在树模型里更接近线性。
const double timeFeatureOffset = 0.5;

/// 把时间转换成模型特征。
double timeFeature(double t) => math.log(t + timeFeatureOffset);

/// 训练标签的变换：ln(C + [logOffset])，让模型在低浓度段也有分辨率。
const double logOffset = 0.001;

/// 把浓度转成训练标签。
double concentrationToTarget(double c) => math.log(math.max(c, 0) + logOffset);

/// 把模型输出还原成浓度。
double targetToConcentration(double y) {
  final v = math.exp(y) - logOffset;
  return v < 0 ? 0 : v;
}

/// 生成血药浓度代理模型的合成训练集。
///
/// 每 [pointsPerCurve] 个采样点来自同一条随机曲线，保证样本间有真实的相关结构。
List<TrainingRow> generateSyntheticDataset({
  int rows = 1400,
  int seed = 7,
  double noise = 0.03,
  int pointsPerCurve = 7,
}) {
  final rng = math.Random(seed);
  final out = <TrainingRow>[];
  final curves = (rows / pointsPerCurve).ceil();

  double logUniform(double lo, double hi) =>
      math.exp(math.log(lo) + rng.nextDouble() * (math.log(hi) - math.log(lo)));

  for (var c = 0; c < curves; c++) {
    final isOral = rng.nextDouble() < 0.5;
    final dose = logUniform(0.5, 1500);
    final vd = logUniform(5, 1200);
    final k = logUniform(0.005, 0.6);
    final ka = logUniform(0.3, 8);
    final f = 0.02 + rng.nextDouble() * 0.98;
    final params = PkParams(
      model: isOral ? PkModel.oneCompOral : PkModel.oneCompIv,
      dose: dose,
      vd: vd,
      k: k,
      ka: ka,
      f: f,
    );
    final profile = PkProfile(params);
    final horizon = math.min(72.0, math.max(8.0, 6 * profile.tHalf));
    const tMin = 0.1;
    for (var p = 0; p < pointsPerCurve; p++) {
      // 第一个点固定 t=0；其余点按对数间隔取样，重点覆盖吸收/分布早期。
      final t = p == 0
          ? 0.0
          : tMin *
              math
                  .pow(horizon / tMin, (p - 1 + rng.nextDouble()) / (pointsPerCurve - 1))
                  .toDouble();
      final c = profile.concentration(t) * (1 + (rng.nextDouble() * 2 - 1) * noise);
      out.add(TrainingRow([
        dose,
        vd,
        k,
        isOral ? ka : 0.0,
        f,
        isOral ? 1.0 : 0.0,
        timeFeature(t),
      ], concentrationToTarget(c)));
    }
  }
  return out;
}

/// CSV 解析结果。
class CsvParseResult {
  const CsvParseResult({required this.points, required this.delimiter, required this.skipped});

  final List<ObservedPoint> points;
  final String delimiter;

  /// 被跳过的行数（表头、空行、无法解析的行）。
  final int skipped;

  bool get isEmpty => points.isEmpty;
}

/// 解析用户粘贴/导入的 CSV：第一列为时间，第二列为浓度。
///
/// 自动识别逗号、分号、制表符或空白分隔，并容忍一行表头。
CsvParseResult parseConcentrationCsv(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  var skipped = 0;
  if (lines.isEmpty) {
    return const CsvParseResult(points: [], delimiter: ',', skipped: 0);
  }

  String delimiter = ',';
  final candidates = [',', ';', '\t'];
  var bestScore = -1;
  for (final d in candidates) {
    var score = 0;
    for (final line in lines.take(6)) {
      final cells = line.split(d).where((c) => c.trim().isNotEmpty).length;
      // 恰好两列最像「时间,浓度」；三列及以上可能是小数点的逗号。
      if (cells == 2) {
        score += 2;
      } else if (cells > 2) {
        score += 1;
      }
    }
    if (score > bestScore) {
      bestScore = score;
      delimiter = d;
    }
  }
  if (bestScore <= 0) delimiter = ' ';

  final points = <ObservedPoint>[];
  for (final line in lines) {
    final cells = line
        .split(delimiter == ' ' ? RegExp(r'\s+') : RegExp(RegExp.escape(delimiter)))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (cells.length < 2) {
      skipped++;
      continue;
    }
    final t = double.tryParse(cells[0].replaceAll(',', '.'));
    final c = double.tryParse(cells[1].replaceAll(',', '.'));
    if (t == null || c == null) {
      skipped++;
      continue;
    }
    points.add(ObservedPoint(t, c));
  }
  points.sort((a, b) => a.t.compareTo(b.t));
  return CsvParseResult(points: points, delimiter: delimiter, skipped: skipped);
}

/// 演示数据：一室口服，D=400 mg，V/F=50 L，k=0.14 h⁻¹，ka=1.1 h⁻¹，带 6% 噪声。
List<ObservedPoint> demoOralData({int seed = 3}) {
  final rng = math.Random(seed);
  final params = PkParams(
    model: PkModel.oneCompOral,
    dose: 400,
    vd: 50,
    k: 0.14,
    ka: 1.1,
    f: 1.0,
  );
  final profile = PkProfile(params);
  const times = <double>[0.5, 1, 1.5, 2, 3, 4, 6, 8, 10, 12, 18, 24];
  return [
    for (final t in times)
      ObservedPoint(t, profile.concentration(t) * (1 + (rng.nextDouble() * 2 - 1) * 0.06)),
  ];
}

/// 把训练集拆成训练 / 验证两份，用于展示模型的泛化误差。
({List<TrainingRow> train, List<TrainingRow> valid}) splitDataset(
  List<TrainingRow> rows, {
  double validRatio = 0.2,
  int seed = 11,
}) {
  final rng = math.Random(seed);
  final copy = List<TrainingRow>.from(rows)..shuffle(rng);
  final cut = (copy.length * (1 - validRatio)).round().clamp(1, copy.length);
  return (train: copy.sublist(0, cut), valid: copy.sublist(cut));
}
