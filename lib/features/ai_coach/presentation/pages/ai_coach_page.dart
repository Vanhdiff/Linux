import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import '../../data/ai_coach_remote_datasource.dart';

class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  final AiCoachRemoteDataSource _dataSource = AiCoachRemoteDataSource();
  AiCoachView _view = AiCoachView.empty();
  String _period = 'day';
  String _language = 'en';
  bool _loading = true;
  String? _error;

  @override
  void dispose() {
    _dataSource.close();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextLanguage = AppLocalization.of(context).isVietnamese ? 'vi' : 'en';
    if (_language != nextLanguage ||
        _loading && _view.context.startDate.isEmpty) {
      _loadReview(language: nextLanguage);
    }
  }

  Future<void> _loadReview({String? period, String? language}) async {
    final nextPeriod = period ?? _period;
    final nextLanguage = language ?? _language;
    setState(() {
      _period = nextPeriod;
      _language = nextLanguage;
      _loading = true;
      _error = null;
    });
    try {
      final view = await _dataSource.fetchReview(
        period: nextPeriod,
        language: nextLanguage,
      );
      if (!mounted) return;
      setState(() {
        _view = view;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 28.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final pageWidth = contentWidth < 1120 ? 1120.0 : contentWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            18,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: pageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _AiHeader(
                    period: _period,
                    loading: _loading,
                    error: _error,
                    onRefresh: () => _loadReview(),
                    onPeriodChanged: (period) => _loadReview(period: period),
                  ),
                  const SizedBox(height: 14),
                  _HeroReviewCard(view: _view),
                  const SizedBox(height: 16),
                  _GuardrailScorePanel(contextData: _view.context),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            _ListPanel(
                              title: 'Key findings',
                              icon: FluentIcons.bulleted_list,
                              items: _view.review.keyFindings,
                              empty:
                                  'No findings yet. Sync more closed trades.',
                            ),
                            const SizedBox(height: 16),
                            _ListPanel(
                              title: 'Coach advice',
                              icon: FluentIcons.lightbulb,
                              items: _view.review.advice,
                              empty: 'No advice yet. Journal a trade first.',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _PlanPanel(plan: _view.review.nextSessionPlan),
                            const SizedBox(height: 16),
                            _DataSignalsPanel(contextData: _view.context),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AiHeader extends StatelessWidget {
  final String period;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<String> onPeriodChanged;

  const _AiHeader({
    required this.period,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        Text(
          strings.text('AI Coach'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            error == null
                ? strings.text(
                    'Journal, guardrails, trades, and news are analyzed from local broker data.',
                  )
                : '${strings.text('AI Coach unavailable')}: $error',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: error == null
                  ? AppColors.textSecondary
                  : AppColors.warning,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        IconButton(
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Icon(FluentIcons.refresh, size: 14),
        ),
        const SizedBox(width: 8),
        _PeriodChip(
          'day',
          strings.text('Today'),
          selected: period == 'day',
          onChanged: onPeriodChanged,
        ),
        const SizedBox(width: 6),
        _PeriodChip(
          'week',
          strings.text('Week'),
          selected: period == 'week',
          onChanged: onPeriodChanged,
        ),
        const SizedBox(width: 6),
        _PeriodChip(
          'month',
          strings.text('Month'),
          selected: period == 'month',
          onChanged: onPeriodChanged,
        ),
      ],
    );
  }
}

class _HeroReviewCard extends StatelessWidget {
  final AiCoachView view;

  const _HeroReviewCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final riskColor = switch (view.review.riskLevel) {
      'high' => AppColors.danger,
      'medium' => AppColors.warning,
      'low' => AppColors.success,
      _ => AppColors.textSecondary,
    };
    final summary = view.context.summary;

    return AppPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(FluentIcons.robot, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _coachText(strings, view.review.headline),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _RiskPill(
                      label: strings.text(_riskLabel(view.review.riskLevel)),
                      color: riskColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Metric(
                      strings.text('Trades'),
                      '${_int(summary['trade_count'])}',
                    ),
                    _Metric(
                      strings.text('Net PnL'),
                      _money(_double(summary['net_pnl'])),
                    ),
                    _Metric(
                      strings.text('Win rate'),
                      '${_double(summary['win_rate']).toStringAsFixed(1)}%',
                    ),
                    _Metric(
                      strings.text('Avg R'),
                      '${_double(summary['average_r']).toStringAsFixed(2)}R',
                    ),
                    _Metric(
                      strings.text('Profit factor'),
                      _double(summary['profit_factor']).toStringAsFixed(2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanPanel extends StatelessWidget {
  final Map<String, dynamic> plan;

  const _PlanPanel({required this.plan});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: FluentIcons.calendar_agenda,
            title: strings.text('Next session plan'),
          ),
          const SizedBox(height: 12),
          _PlanRow(strings.text('Max trades'), '${plan['max_trades'] ?? '-'}'),
          _PlanRow(
            strings.text('Risk/trade'),
            '${plan['risk_per_trade'] ?? '-'}',
          ),
          _PlanRow(
            strings.text('Focus'),
            _coachText(strings, '${plan['focus'] ?? '-'}'),
          ),
          _PlanRow(strings.text('Avoid'), _avoidText(strings, plan['avoid'])),
        ],
      ),
    );
  }

  String _avoidText(AppStrings strings, Object? value) {
    if (value is List && value.isNotEmpty) return value.join(', ');
    return strings.text('No forced avoidance');
  }
}

class _DataSignalsPanel extends StatelessWidget {
  final AiCoachContext contextData;

  const _DataSignalsPanel({required this.contextData});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: FluentIcons.database,
            title: strings.text('Data signals'),
          ),
          const SizedBox(height: 12),
          _SignalGroup(
            title: strings.text('Mistakes'),
            items: contextData.mistakes,
            valueKey: 'count',
          ),
          const SizedBox(height: 12),
          _SignalGroup(
            title: strings.text('Weakest symbols'),
            items: contextData.symbols.take(3).toList(),
            valueKey: 'net_pnl',
            money: true,
          ),
          const SizedBox(height: 12),
          _SignalGroup(
            title: strings.text('Rule breaks'),
            items: contextData.ruleBreaks,
            nameKey: 'rule_code',
            valueKey: 'count',
          ),
        ],
      ),
    );
  }
}

class _GuardrailScorePanel extends StatelessWidget {
  final AiCoachContext contextData;

  const _GuardrailScorePanel({required this.contextData});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final guardrails = contextData.guardrails;
    final scorecard =
        guardrails['scorecard'] as Map<String, dynamic>? ?? const {};
    final categories = _maps(scorecard['categories']);
    final lock =
        guardrails['guardrail_lock'] as Map<String, dynamic>? ?? const {};
    final pending = lock['pending_update'] as Map<String, dynamic>?;
    final blockingEnabled =
        scorecard['trade_blocking_enabled'] as bool? ??
        guardrails['trade_blocking_enabled'] as bool? ??
        false;

    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PanelTitle(
                icon: FluentIcons.shield,
                title: strings.text('AI Coach rules'),
              ),
              const Spacer(),
              _RiskPill(
                label: blockingEnabled ? 'Blocktrade on' : 'Blocktrade off',
                color: blockingEnabled ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _CompactMetric(
                label: strings.text('Score'),
                value:
                    '${_double(scorecard['total_points']).toStringAsFixed(1)}/${_double(scorecard['max_points']).toStringAsFixed(1)}',
              ),
              _CompactMetric(
                label: strings.text('Trade block'),
                value: guardrails['trade_blocked'] == true
                    ? 'Blocked'
                    : 'Clear',
              ),
              _CompactMetric(
                label: strings.text('Today lock'),
                value: lock['effective_today_locked'] == true
                    ? 'Locked'
                    : 'Editable',
              ),
              if (pending != null)
                _CompactMetric(
                  label: strings.text('Next apply'),
                  value: '${pending['effective_date'] ?? '-'}',
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${lock['message'] ?? ''}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          if (categories.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              strings.text('No data yet'),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 16),
            for (final category in categories) ...[
              _GuardrailCategoryCard(category: category),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}

class _GuardrailCategoryCard extends StatelessWidget {
  final Map<String, dynamic> category;

  const _GuardrailCategoryCard({required this.category});

  @override
  Widget build(BuildContext context) {
    final rows = _maps(category['rows']);
    final forcedZero = category['forced_zero'] as bool? ?? false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${category['label'] ?? '-'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_double(category['earned_points']).toStringAsFixed(1)}/${_double(category['max_points']).toStringAsFixed(1)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (forcedZero) ...[
            const SizedBox(height: 6),
            Text(
              '${category['reason'] ?? ''}',
              style: TextStyle(color: AppColors.warning, fontSize: 11),
            ),
          ],
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GuardrailRuleRow(row: row),
            ),
        ],
      ),
    );
  }
}

class _GuardrailRuleRow extends StatelessWidget {
  final Map<String, dynamic> row;

  const _GuardrailRuleRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final passed = row['passed'] as bool? ?? false;
    final color = passed ? AppColors.success : AppColors.danger;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          passed ? FluentIcons.check_mark : FluentIcons.chrome_close,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${row['label'] ?? '-'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_guardrailValue(row['value'], row['unit'])} / ${_guardrailValue(row['target'], row['unit'])}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${_double(row['earned_points']).toStringAsFixed(1)}/${_double(row['max_points']).toStringAsFixed(1)}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _CompactMetric extends StatelessWidget {
  final String label;
  final String value;

  const _CompactMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ListPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;
  final String empty;

  const _ListPanel({
    required this.title,
    required this.icon,
    required this.items,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(icon: icon, title: strings.text(title)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              strings.text(empty),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            for (final item in items) _BulletLine(_coachText(strings, item)),
        ],
      ),
    );
  }
}

class _SignalGroup extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final String nameKey;
  final String valueKey;
  final bool money;

  const _SignalGroup({
    required this.title,
    required this.items,
    this.nameKey = 'name',
    required this.valueKey,
    this.money = false,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        if (items.isEmpty)
          Text(
            strings.text('No data yet'),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          )
        else
          for (final item in items)
            _PlanRow(
              '${item[nameKey] ?? '-'}',
              money
                  ? _money(_double(item[valueKey]))
                  : '${item[valueKey] ?? '-'}',
            ),
      ],
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _BulletLine extends StatelessWidget {
  final String text;

  const _BulletLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  final String label;
  final String value;

  const _PlanRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _RiskPill extends StatelessWidget {
  final String label;
  final Color color;

  const _RiskPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final ValueChanged<String> onChanged;

  const _PeriodChip(
    this.value,
    this.label, {
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

List<Map<String, dynamic>> _maps(Object? value) {
  return (value as List<dynamic>? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

String _money(double value) {
  final sign = value > 0
      ? '+'
      : value < 0
      ? '-'
      : '';
  return '$sign\$${value.abs().toStringAsFixed(0)}';
}

String _guardrailValue(Object? value, Object? unit) {
  final normalizedUnit = '$unit';
  final number = _double(value);
  if (normalizedUnit == r'$') {
    return '${number < 0 ? '-' : ''}\$${number.abs().toStringAsFixed(2)}';
  }
  if (normalizedUnit == '%') {
    return '${number.toStringAsFixed(2)}%';
  }
  if (normalizedUnit == 'R') {
    return '${number.toStringAsFixed(2)}R';
  }
  if (normalizedUnit == 'trades' || normalizedUnit == 'losses') {
    return _int(value).toString();
  }
  if (value is num) {
    return number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2);
  }
  return '${value ?? '-'}';
}

String _riskLabel(String value) {
  return switch (value) {
    'high' => 'High risk',
    'medium' => 'Medium risk',
    'low' => 'Low risk',
    _ => 'Neutral',
  };
}

String _coachText(AppStrings strings, String value) {
  if (!strings.isVietnamese) return value;
  final exact = strings.text(value);
  if (exact != value) return exact;

  RegExpMatch? match = RegExp(
    r'^Closed (\d+) trades with net PnL ([^ ]+) and win rate ([\d.]+)%\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'ÄĂ£ Ä‘Ă³ng ${match[1]} lá»‡nh vá»›i PnL rĂ²ng ${match[2]} vĂ  tá»· lá»‡ tháº¯ng ${match[3]}%.';
  }

  match = RegExp(
    r'^Average R is ([^ ]+) and profit factor is ([^ ]+)\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'R trung bĂ¬nh lĂ  ${match[1]} vĂ  há»‡ sá»‘ lá»£i nhuáº­n lĂ  ${match[2]}.';
  }

  match = RegExp(
    r'^(.+) is the weakest symbol in this period at (.+)\.$',
  ).firstMatch(value);
  if (match != null) {
    return '${match[1]} lĂ  mĂ£ yáº¿u nháº¥t trong ká»³ nĂ y vá»›i ${match[2]}.';
  }

  match = RegExp(r'^(.+) is the strongest symbol at (.+)\.$').firstMatch(value);
  if (match != null) {
    return '${match[1]} lĂ  mĂ£ máº¡nh nháº¥t vá»›i ${match[2]}.';
  }

  match = RegExp(
    r'^Reduce or pause (.+) until the next review',
  ).firstMatch(value);
  if (match != null) {
    return 'Giáº£m hoáº·c táº¡m dá»«ng ${match[1]} cho Ä‘áº¿n láº§n review tiáº¿p theo, trá»« khi cĂ³ setup A+ Ä‘Ă£ Ä‘Æ°á»£c viáº¿t rĂµ.';
  }

  match = RegExp(
    r'^Review (.+) session entries; this session contributed (.+)\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'Review cĂ¡c Ä‘iá»ƒm vĂ o lá»‡nh phiĂªn ${match[1]}; phiĂªn nĂ y Ä‘Ă³ng gĂ³p ${match[2]}.';
  }

  match = RegExp(
    r'^Most repeated journal mistake: (.+) \((\d+)x\)\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'Lá»—i journal láº·p láº¡i nhiá»u nháº¥t: ${match[1]} (${match[2]} láº§n).';
  }

  match = RegExp(
    r"^Before the next trade, explicitly check: am I repeating '(.+)'\?$",
  ).firstMatch(value);
  if (match != null) {
    return 'TrÆ°á»›c lá»‡nh tiáº¿p theo, hĂ£y kiá»ƒm tra rĂµ: mĂ¬nh cĂ³ Ä‘ang láº·p láº¡i "${match[1]}" khĂ´ng?';
  }

  match = RegExp(
    r'^(\d+) rule break types were detected in this period\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'PhĂ¡t hiá»‡n ${match[1]} loáº¡i vi pháº¡m rule trong ká»³ nĂ y.';
  }

  match = RegExp(
    r'^Replay the worst trade \((.+) (.+)\) before taking another similar setup\.$',
  ).firstMatch(value);
  if (match != null) {
    return 'Xem láº¡i lá»‡nh tá»‡ nháº¥t (${match[1]} ${match[2]}) trÆ°á»›c khi vĂ o setup tÆ°Æ¡ng tá»±.';
  }

  return value;
}

