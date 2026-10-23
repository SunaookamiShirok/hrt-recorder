// 参数反推页：粘贴实测数据 → 拟合 ka / k / V。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/dataset.dart';
import '../../core/fitting.dart';
import '../../core/pk.dart';
import '../../data/lab_store.dart';
import '../../utils/format.dart';
import '../unit_scope.dart';
import '../widgets/chart.dart';
import '../widgets/common.dart';
import '../widgets/page_layout.dart';

/// 拟合模式：普通口服、静注、储库（flip-flop，允许 ka < k）、含服（双吸收相）。
enum _FitMode {
  oral('口服'),
  iv('静注'),
  depot('储库'),
  sublingual('含服');

  const _FitMode(this.label);

  final String label;
}

class FittingPage extends StatefulWidget {
  const FittingPage({super.key});

  @override
  State<FittingPage> createState() => _FittingPageState();
}

class _FittingPageState extends State<FittingPage> {
  final TextEditingController _csvController = TextEditingController();
  double _dose = 400;
  _FitMode _mode = _FitMode.oral;

  /// 储库 / 含服模式下的已知消除常数 (h⁻¹)。
  double _knownK = 0.09;

  /// 含服模式下固定的快相吸收速率 (h⁻¹)。
  double _fastKa = 5.0;
  FitResult? _result;
  List<ObservedPoint> _points = const [];
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _csvController.text = _toCsv(demoOralData());
    _notice = '已载入演示数据（含 6% 随机误差），可直接点击「开始拟合」。';
    // 首帧后自动对演示数据拟合一次，打开页面就能看到结果。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _runFit();
    });
  }

  @override
  void dispose() {
    _csvController.dispose();
    super.dispose();
  }

  String _toCsv(List<ObservedPoint> points) {
    final b = StringBuffer('time,conc\n');
    for (final p in points) {
      b.writeln('${p.t},${p.c.toStringAsFixed(3)}');
    }
    return b.toString().trimRight();
  }

  void _loadDemo() {
    setState(() {
      _csvController.text = _toCsv(demoOralData());
      _mode = _FitMode.oral;
      _result = null;
      _error = null;
      _notice = '已载入演示数据（真实参数：ka=1.1、k=0.14、V/F=50 L，含 6% 噪声）。';
    });
  }

  /// 把「化验记录」里带「距给药 (h)」的记录导入到拟合数据。
  Future<void> _importFromLab() async {
    await LabStore.instance.ensureLoaded();
    if (!mounted) return;
    final tagged = [
      for (final r in LabStore.instance.records)
        if (r.hoursSinceDose != null) r,
    ];
    if (tagged.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('化验记录里还没有填写「距上次给药 (h)」的记录')),
      );
      return;
    }
    final analytes = <String>{for (final r in tagged) r.analyte}.toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择要导入的指标'),
        children: [
          for (final a in analytes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, a),
              child: Text('$a（${tagged.where((r) => r.analyte == a).length} 条）'),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final chosen = tagged.where((r) => r.analyte == choice).toList()
      ..sort((a, b) => a.hoursSinceDose!.compareTo(b.hoursSinceDose!));
    final csv = StringBuffer('time,conc\n');
    for (final r in chosen) {
      csv.writeln('${r.hoursSinceDose},${r.valueMgPerL}');
    }
    setState(() {
      _csvController.text = csv.toString();
      _notice = '已导入 ${chosen.length} 条 $choice 化验记录（浓度单位 mg/L）。';
    });
    _runFit();
  }

  void _runFit() {
    final parsed = parseConcentrationCsv(_csvController.text);
    if (parsed.points.length < 4) {
      setState(() {
        _error = '至少需要 4 个有效数据点（当前 ${parsed.points.length} 个）。';
        _result = null;
      });
      return;
    }
    final fitter = PkFitter(points: parsed.points, dose: _dose);
    final result = switch (_mode) {
      _FitMode.oral => fitter.fitOral(),
      _FitMode.depot => fitter.fitOral(allowFlipFlop: true, fixedK: _knownK),
      _FitMode.sublingual => fitter.fitDual(fixedK: _knownK, fastKa: _fastKa),
      _FitMode.iv => fitter.fitIv(),
    };
    setState(() {
      _points = parsed.points;
      _result = result;
      _error = null;
      _notice = parsed.skipped > 0
          ? '已忽略 ${parsed.skipped} 行无法解析的内容（表头或空行属于正常情况）。'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unit = UnitScope.of(context);
    final modelParams = _result?.params;
    final result = _result;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('参数反推（曲线拟合）',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(
          '输入实测「时间-浓度」数据点，用加权最小二乘反推药动学参数',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: '拟合结果',
          subtitle: _result == null ? '点击右侧「开始拟合」' : '曲线为拟合值，圆点为实测值',
          icon: Icons.auto_graph,
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
          child: ConcentrationChart(
            series: [
              if (result != null && modelParams != null)
                ChartSeries(
                  points: convertSamples(
                    result.curve(
                      duration: (_points.map((p) => p.t).fold(0.0, (a, b) => a > b ? a : b) * 1.25)
                          .clamp(4.0, 240.0)
                          .toDouble(),
                      points: 400,
                    ),
                    unit,
                  ),
                  color: scheme.primary,
                  fill: true,
                  label: '拟合曲线',
                ),
            ],
            markers: [
              for (final p in _points) ChartMarker(p.t, unit.convert(p.c)),
            ],
            yUnit: unit.label,
            height: 340,
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InfoBanner(icon: Icons.error_outline, text: _error!),
          ),
        if (result != null) ...[
          _metricsGrid(context, result),
          const SizedBox(height: 14),
          _residualTable(context, result),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            InfoBanner(text: _notice!),
          ],
        ],
      ],
    );

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: '拟合设置',
          icon: Icons.settings_suggest_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_FitMode>(
                segments: const [
                  ButtonSegment(
                    value: _FitMode.oral,
                    label: Text('口服'),
                    icon: Icon(Icons.water_drop_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: _FitMode.iv,
                    label: Text('静注'),
                    icon: Icon(Icons.bolt_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: _FitMode.depot,
                    label: Text('储库'),
                    icon: Icon(Icons.hourglass_bottom, size: 16),
                  ),
                  ButtonSegment(
                    value: _FitMode.sublingual,
                    label: Text('含服'),
                    icon: Icon(Icons.bubble_chart_outlined, size: 16),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 10),
              ParamField(
                label: '已知给药剂量 D',
                unit: 'mg',
                value: _dose,
                onChanged: (v) => setState(() => _dose = v),
              ),
              if (_mode == _FitMode.depot || _mode == _FitMode.sublingual) ...[
                const SizedBox(height: 10),
                ParamField(
                  label: '已知消除常数 k',
                  unit: 'h⁻¹',
                  value: _knownK,
                  onChanged: (v) => setState(() => _knownK = v),
                ),
              ],
              if (_mode == _FitMode.sublingual) ...[
                const SizedBox(height: 10),
                ParamField(
                  label: '固定快相 ka1',
                  unit: 'h⁻¹',
                  value: _fastKa,
                  onChanged: (v) => setState(() => _fastKa = v),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                switch (_mode) {
                  _FitMode.oral => '口服模型拟合 ka、k、V/F（三者由曲线形状决定）',
                  _FitMode.iv => '静注模型拟合 C₀ 与 k，再换算 V = D / C₀',
                  _FitMode.depot => '储库/缓释：固定已知的消除常数 k，只拟合释放速率 ka，'
                      '可得到 ka < k 的 flip-flop 曲线（肌注油剂等）',
                  _FitMode.sublingual => '含服/复方：固定 k 与快相 ka1，拟合慢相 ka2 与快相占比 F1，'
                      '能同时描述早期尖峰和后段拖尾',
                },
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '实测数据',
          subtitle: '每行「时间,浓度」，支持逗号/分号/制表符',
          icon: Icons.edit_note,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _csvController,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _runFit,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('开始拟合'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '从化验记录导入',
                    onPressed: _importFromLab,
                    icon: const Icon(Icons.biotech_outlined),
                  ),
                  IconButton(
                    tooltip: '载入演示数据',
                    onPressed: _loadDemo,
                    icon: const Icon(Icons.science_outlined),
                  ),
                  IconButton(
                    tooltip: '复制数据',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _csvController.text));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制到剪贴板')),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const InfoBanner(
          text: '拟合采用相对误差加权 + 网格粗搜 + Nelder–Mead 精修，'
              '对初值不敏感；R² 越接近 1 说明模型越贴合数据。',
        ),
      ],
    );

    return ResponsivePage(controls: controls, body: body);
  }

  Widget _metricsGrid(BuildContext context, FitResult r) {
    final p = r.params;
    final unit = UnitScope.of(context);
    final isOral = _mode != _FitMode.iv;
    final profile = PkProfile(p);
    final sim = PkSimulator(PkScenario(params: p));
    final metrics = sim.singleDoseMetrics(profile.tHalf * 8);
    final tiles = <Widget>[
      MetricTile(
        label: 'R²',
        value: fmtNum(r.r2, maxSignificant: 4),
        hint: '决定系数',
        color: Theme.of(context).colorScheme.primary,
      ),
      MetricTile(label: 'k', value: fmtNum(p.k), unit: 'h⁻¹', hint: '消除速率常数'),
      if (isOral) MetricTile(label: 'ka', value: fmtNum(p.ka), unit: 'h⁻¹', hint: '吸收速率常数'),
      if (_mode == _FitMode.sublingual) ...[
        MetricTile(label: 'ka2', value: fmtNum(p.ka2), unit: 'h⁻¹', hint: '慢相吸收'),
        MetricTile(label: 'F1', value: fmtNum(p.fFast, maxSignificant: 3), hint: '快相占比'),
      ],
      MetricTile(
        label: isOral ? 'V/F' : 'V',
        value: fmtNum(p.vd),
        unit: 'L',
        hint: isOral ? '表观分布容积' : '分布容积',
      ),
      MetricTile(label: 't½', value: fmtNum(profile.tHalf), unit: 'h', hint: '拟合半衰期'),
      MetricTile(label: 'CL', value: fmtNum(profile.clearance), unit: 'L/h', hint: '清除率'),
      MetricTile(label: 'Cmax(拟合)', value: unit.format(metrics.cMax), unit: unit.label),
      MetricTile(label: 'Tmax(拟合)', value: fmtNum(metrics.tMax), unit: 'h'),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = (c.maxWidth / 190).floor().clamp(1, 6);
        final width = (c.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in tiles) SizedBox(width: width, child: t),
          ],
        );
      },
    );
  }

  Widget _residualTable(BuildContext context, FitResult r) {
    final unit = UnitScope.of(context);
    return SectionCard(
      title: '实测值 vs 拟合值',
      icon: Icons.compare_arrows,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 36,
          columnSpacing: 26,
          columns: [
            const DataColumn(label: Text('t (h)')),
            DataColumn(label: Text('实测 (${unit.label})')),
            DataColumn(label: Text('拟合 (${unit.label})')),
            const DataColumn(label: Text('残差 (%)')),
          ],
          rows: [
            for (var i = 0; i < _points.length; i++)
              DataRow(cells: [
                DataCell(Text(fmtNum(_points[i].t, maxSignificant: 4))),
                DataCell(Text(unit.format(_points[i].c))),
                DataCell(Text(unit.format(r.predicted[i]))),
                DataCell(Text(
                  _points[i].c <= 0
                      ? '—'
                      : fmtNum((r.predicted[i] - _points[i].c) / _points[i].c * 100,
                          maxSignificant: 3),
                )),
              ]),
          ],
        ),
      ),
    );
  }
}
