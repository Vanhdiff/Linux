import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../app/services/api/api_exception.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/guardrails_remote_datasource.dart';

class GuardrailsPage extends StatefulWidget {
  const GuardrailsPage({super.key});

  @override
  State<GuardrailsPage> createState() => _GuardrailsPageState();
}

class _GuardrailsPageState extends State<GuardrailsPage> {
  int get _accountId => ActiveAccountSession.accountId;

  final _remote = GuardrailsRemoteDataSource();
  final _maxTradesController = TextEditingController(text: '5');
  final _maxDailyLossController = TextEditingController(text: '3000');
  final _maxDailyProfitController = TextEditingController(text: '5000');
  final _riskController = TextEditingController(text: '0.5');
  final _windowStartController = TextEditingController(text: '07:00');
  final _windowEndController = TextEditingController(text: '10:00');
  final _newsMinutesController = TextEditingController(text: '30');

  Map<String, dynamic>? _status;
  Map<String, dynamic>? _mt5BlockerStatus;
  String _newsMode = 'Before and After';
  bool _tradeBlockingEnabled = false;
  bool _blockHighImpactNews = true;
  bool _loading = true;
  bool _saving = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _maxTradesController.dispose();
    _maxDailyLossController.dispose();
    _maxDailyProfitController.dispose();
    _riskController.dispose();
    _windowStartController.dispose();
    _windowEndController.dispose();
    _newsMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 22.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final pageWidth = contentWidth < 1120 ? 1120.0 : contentWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            24,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: pageWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    status: _status,
                    loading: _loading,
                    onRefresh: _loadStatus,
                  ),
                  const SizedBox(height: 14),
                  _StatusStrip(status: _status),
                  const SizedBox(height: 14),
                  _BlockBanner(status: _status),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: _buildSettingsPanel()),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 9,
                        child: _RulesPanel(
                          status: _status,
                          mt5BlockerStatus: _mt5BlockerStatus,
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

  Widget _buildSettingsPanel() {
    final strings = AppLocalization.of(context);
    final hardLocked = _guardrailsHardLocked;
    final lockMessage = _guardrailLockMessage;
    return _Panel(
      title: strings.text('Trade blocking rules'),
      subtitle: strings.text(
        'Guardrails can block app/EA trade execution automatically once enabled.',
      ),
      child: Column(
        children: [
          _SettingRow(
            icon: FluentIcons.lock,
            title: strings.text('Enable trade blocking'),
            description: strings.text(
              'Blocks new orders when an active limit is reached',
            ),
            control: ToggleSwitch(
              checked: _tradeBlockingEnabled,
              onChanged: hardLocked
                  ? null
                  : (value) => setState(() => _tradeBlockingEnabled = value),
            ),
          ),
          _SettingRow(
            icon: FluentIcons.number_field,
            title: strings.text('Max trades per day'),
            description: strings.text(
              'Stop overtrading by limiting completed trades',
            ),
            control: _Field(
              controller: _maxTradesController,
              suffix: 'trades',
              enabled: !hardLocked,
            ),
          ),
          _SettingRow(
            icon: FluentIcons.money,
            title: strings.text('Max daily loss'),
            description: strings.text(
              'Uses realized P&L from normalized trades',
            ),
            control: _Field(
              controller: _maxDailyLossController,
              prefix: r'$',
              enabled: !hardLocked,
            ),
          ),
          _SettingRow(
            icon: FluentIcons.savings,
            title: strings.text('Max daily profit'),
            description: strings.text(
              'Locks in discipline once the target is reached',
            ),
            control: _Field(
              controller: _maxDailyProfitController,
              prefix: r'$',
              enabled: !hardLocked,
            ),
          ),
          _SettingRow(
            icon: FluentIcons.speed_high,
            title: strings.text('Fixed risk per trade'),
            description: strings.text(
              'Stored for position sizing and risk warnings',
            ),
            control: _Field(
              controller: _riskController,
              suffix: '%',
              enabled: !hardLocked,
            ),
          ),
          _SettingRow(
            icon: FluentIcons.clock,
            title: strings.text('Trading window'),
            description: strings.text(
              'Used for local warnings outside planned sessions',
            ),
            control: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const _TimeZoneBadge(),
                _Field(
                  controller: _windowStartController,
                  width: 64,
                  enabled: !hardLocked,
                ),
                _Field(
                  controller: _windowEndController,
                  width: 64,
                  enabled: !hardLocked,
                ),
              ],
            ),
          ),
          _SettingRow(
            icon: FluentIcons.news,
            title: strings.text('High-impact news block'),
            description: strings.text(
              'Blocks red news only - 15 min before & after - yellow allowed',
            ),
            control: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleSwitch(
                  checked: _blockHighImpactNews,
                  onChanged: hardLocked
                      ? null
                      : (value) => setState(() => _blockHighImpactNews = value),
                ),
                _Select(
                  value: _newsMode,
                  values: const [
                    'Before and After',
                    'Before only',
                    'After only',
                  ],
                  width: 150,
                  onChanged: hardLocked
                      ? null
                      : (value) => setState(() => _newsMode = value),
                ),
                _Field(
                  controller: _newsMinutesController,
                  width: 56,
                  suffix: 'm',
                  enabled: !hardLocked,
                ),
              ],
            ),
          ),
          if (lockMessage != null) ...[
            const SizedBox(height: 12),
            _Notice(text: lockMessage),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            _Notice(text: _notice!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _OutlineAction(
                label: strings.text('Reset defaults'),
                onTap: hardLocked ? null : _resetDefaults,
              ),
              const Spacer(),
              _PrimaryAction(
                label: hardLocked
                    ? strings.text('Locked')
                    : (_saving
                          ? strings.text('Saving...')
                          : strings.text('Save guardrails')),
                onTap: _saving || hardLocked ? null : _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _notice = null;
    });

    try {
      final status = await _remote.fetchStatus(accountId: _accountId);
      Map<String, dynamic>? blockerStatus;
      try {
        blockerStatus = await _remote.fetchMt5TradeBlockerStatus();
      } catch (_) {
        blockerStatus = null;
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _mt5BlockerStatus = blockerStatus;
        _applySettings(status['settings'] as Map<String, dynamic>?);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = 'Backend offline - editing recommended local defaults.';
      });
    }
  }

  Future<void> _save() async {
    final maxTrades = int.tryParse(_maxTradesController.text.trim());
    final maxLoss = double.tryParse(_maxDailyLossController.text.trim());
    final maxProfit = double.tryParse(_maxDailyProfitController.text.trim());
    final fixedRisk = double.tryParse(_riskController.text.trim());
    final newsMinutes = int.tryParse(_newsMinutesController.text.trim());

    if (maxTrades == null ||
        maxLoss == null ||
        maxProfit == null ||
        fixedRisk == null ||
        newsMinutes == null) {
      setState(() => _notice = 'Please enter valid numeric guardrails.');
      return;
    }

    setState(() {
      _saving = true;
      _notice = null;
    });

    try {
      await _remote.saveSettings(
        accountId: _accountId,
        maxTradesPerDay: maxTrades,
        maxDailyLoss: maxLoss,
        maxDailyProfit: maxProfit,
        fixedRiskPercent: fixedRisk,
        tradingWindowStart: 'UTC+7 ${_windowStartController.text.trim()}',
        tradingWindowEnd: 'UTC+7 ${_windowEndController.text.trim()}',
        newsBlockMode: _newsMode,
        newsWindowMinutes: newsMinutes,
        tradeBlockingEnabled: _tradeBlockingEnabled,
        blockMaxTrades: true,
        blockMaxDailyLoss: true,
        blockMaxDailyProfit: true,
        blockHighImpactNews: _blockHighImpactNews,
      );
      await _loadStatus();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = _tradeBlockingEnabled
            ? 'Guardrails saved. MT5 trade blocker will enforce active limits.'
            : 'Guardrails saved. Trade blocking is currently off.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = _saveErrorMessage(error);
      });
    }
  }

  bool get _guardrailsHardLocked {
    final lock = _status?['guardrail_lock'] as Map<String, dynamic>?;
    return lock?['hard_locked'] as bool? ?? false;
  }

  String? get _guardrailLockMessage {
    final lock = _status?['guardrail_lock'] as Map<String, dynamic>?;
    if (lock == null) return null;
    final message = lock['message'] as String?;
    if (message == null || message.isEmpty) return null;
    final hardLocked = lock['hard_locked'] as bool? ?? false;
    final tightenOnly = lock['tighten_only'] as bool? ?? false;
    if (!hardLocked && !tightenOnly) return null;
    return message;
  }

  String _saveErrorMessage(Object error) {
    if (error is ApiException) {
      try {
        final body = jsonDecode(error.message);
        if (body is Map<String, dynamic>) {
          final detail = body['detail'];
          if (detail is String && detail.isNotEmpty) return detail;
        }
      } catch (_) {
        // Fall through to the raw exception message.
      }
      return error.message;
    }
    return 'Could not save guardrails. Backend may be offline.';
  }

  void _resetDefaults() {
    setState(() {
      _maxTradesController.text = '5';
      _maxDailyLossController.text = '3000';
      _maxDailyProfitController.text = '5000';
      _riskController.text = '0.5';
      _windowStartController.text = '07:00';
      _windowEndController.text = '10:00';
      _newsMinutesController.text = '30';
      _newsMode = 'Before and After';
      _tradeBlockingEnabled = false;
      _blockHighImpactNews = true;
      _notice = null;
    });
  }

  void _applySettings(Map<String, dynamic>? settings) {
    if (settings == null) return;
    final nested = settings['settings'] as Map<String, dynamic>? ?? {};
    final pending = nested['pending_update'] as Map<String, dynamic>?;
    final pendingChanges = pending?['changes'] as Map<String, dynamic>?;
    final pendingNested =
        pendingChanges?['settings'] as Map<String, dynamic>? ?? {};
    final effectiveMaxTrades =
        pendingChanges?['max_trades_per_day'] ?? settings['max_trades_per_day'];
    final effectiveMaxDailyLoss =
        pendingChanges?['max_daily_loss'] ?? settings['max_daily_loss'];
    final effectiveBlockHighImpactNews =
        pendingChanges?['block_high_impact_news'] ??
        settings['block_high_impact_news'];
    final effectiveWindowStart =
        pendingChanges?['trading_window_start'] ??
        settings['trading_window_start'];
    final effectiveWindowEnd =
        pendingChanges?['trading_window_end'] ?? settings['trading_window_end'];

    _maxTradesController.text = '${(effectiveMaxTrades as num?)?.toInt() ?? 5}';
    _maxDailyLossController.text =
        '${((effectiveMaxDailyLoss ?? 3000) as num).toDouble().round()}';
    _maxDailyProfitController.text =
        '${((pendingNested['max_daily_profit'] ?? nested['max_daily_profit'] ?? 5000) as num).toDouble().round()}';
    _riskController.text =
        '${((pendingNested['fixed_risk_percent'] ?? nested['fixed_risk_percent'] ?? 0.5) as num).toDouble()}';
    _newsMinutesController.text =
        '${((pendingNested['news_window_minutes_before'] ?? nested['news_window_minutes_before'] ?? 30) as num).toInt()}';
    _newsMode =
        pendingNested['news_block_mode'] as String? ??
        nested['news_block_mode'] as String? ??
        _newsMode;
    _tradeBlockingEnabled =
        pendingNested['trade_blocking_enabled'] as bool? ??
        nested['trade_blocking_enabled'] as bool? ??
        false;
    _blockHighImpactNews = effectiveBlockHighImpactNews as bool? ?? true;
    _parseWindow(effectiveWindowStart as String?, true);
    _parseWindow(effectiveWindowEnd as String?, false);
  }

  void _parseWindow(String? value, bool start) {
    if (value == null || value.isEmpty) return;
    final parts = value.split(' ');
    if (parts.length >= 2) {
      if (start) {
        _windowStartController.text = parts.last;
      } else {
        _windowEndController.text = parts.last;
      }
    }
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic>? status;
  final bool loading;
  final VoidCallback onRefresh;

  const _Header({
    required this.status,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final summary = status?['summary'] as Map<String, dynamic>? ?? {};
    final critical = (summary['critical_count'] as num?)?.toInt() ?? 0;

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('Account protection'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              strings.text(
                'Automated limits that keep your trading inside the plan, enforced directly on MT5.',
              ),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (critical > 0)
          _AttentionPill(
            text: '$critical ${strings.text('critical rule needs attention')}',
          ),
        const SizedBox(width: 10),
        _IconAction(
          icon: loading ? FluentIcons.sync : FluentIcons.refresh,
          onTap: onRefresh,
        ),
      ],
    );
  }
}

class _AttentionPill extends StatelessWidget {
  final String text;

  const _AttentionPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.warning, size: 12, color: AppColors.warning),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: AppColors.warning,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  final Map<String, dynamic>? status;

  const _StatusStrip({required this.status});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final summary = status?['summary'] as Map<String, dynamic>? ?? {};
    final triggered = (summary['triggered_count'] as num?)?.toInt() ?? 0;
    final critical = (summary['critical_count'] as num?)?.toInt() ?? 0;
    final mode = status?['mode'] as String? ?? 'local_read_only';
    final blocking = status?['trade_blocking_enabled'] as bool? ?? false;
    final blocked = status?['trade_blocked'] as bool? ?? false;

    return Row(
      children: [
        Expanded(
          child: _StatusCard(
            icon: FluentIcons.lock,
            label: strings.text('Trade blocking'),
            value: blocked
                ? strings.text('Blocked')
                : (blocking ? strings.text('Ready') : strings.text('Off')),
            color: blocked
                ? AppColors.danger
                : (blocking ? AppColors.warning : AppColors.success),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusCard(
            icon: FluentIcons.shield,
            label: strings.text('Mode'),
            value: strings.text(_modeLabel(mode)),
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusCard(
            icon: FluentIcons.warning,
            label: strings.text('Triggered rules'),
            value: '$triggered ${strings.text('active')}',
            color: triggered > 0 ? AppColors.warning : AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatusCard(
            icon: FluentIcons.error_badge,
            label: strings.text('Critical'),
            value: '$critical ${strings.text('critical')}',
            color: critical > 0 ? AppColors.danger : AppColors.success,
          ),
        ),
      ],
    );
  }
}

String _modeLabel(String value) {
  final text = value.replaceAll('_', ' ');
  if (text.isEmpty) return text;
  return text[0].toUpperCase() + text.substring(1);
}

class _RulesPanel extends StatelessWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? mt5BlockerStatus;

  const _RulesPanel({required this.status, required this.mt5BlockerStatus});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final checks = status?['checks'] as List<dynamic>? ?? const [];
    final mt5Issue = _mt5TradeBlockerIssue(mt5BlockerStatus);
    final tiles = <Widget>[
      if (mt5Issue != null)
        _RuleTile(
          code: 'mt5_autotrading_disabled',
          message: mt5Issue,
          triggered: true,
          severity: 'critical',
        ),
      ...checks.map((item) {
        final json = item as Map<String, dynamic>;
        return _RuleTile(
          code: json['rule_code'] as String? ?? 'rule',
          message: json['message'] as String? ?? '',
          triggered: json['triggered'] as bool? ?? false,
          severity: json['severity'] as String? ?? 'info',
        );
      }),
    ];

    return _Panel(
      title: strings.text('Live rule checks'),
      subtitle: strings.text(
        'Reads local analytics and cached economic news in real time.',
      ),
      child: tiles.isEmpty ? _EmptyRules() : Column(children: tiles),
    );
  }

  String? _mt5TradeBlockerIssue(Map<String, dynamic>? status) {
    final accounts = status?['accounts'] as Map<String, dynamic>?;
    final account = accounts?['1'] as Map<String, dynamic>?;
    final action = account?['mt5_action'] as Map<String, dynamic>?;
    final failedActions =
        action?['failed_actions'] as List<dynamic>? ?? const [];
    for (final item in failedActions) {
      final failedAction = item as Map<String, dynamic>;
      final result = failedAction['result'] as Map<String, dynamic>?;
      final retcode = (result?['retcode'] as num?)?.toInt();
      final comment = result?['comment'] as String? ?? '';
      if (retcode == 10027 || comment.contains('AutoTrading disabled')) {
        return 'MT5 AutoTrading is off. Enable Algo Trading in MT5 so the blocker can close rejected trades.';
      }
    }
    final error = action?['error'] as String?;
    if (error != null && error.isNotEmpty) {
      return 'MT5 blocker error: $error';
    }
    return null;
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget control;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.control,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.75)),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final titleBlock = Row(
            children: [
              Container(
                width: 34,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 14, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: control),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Align(alignment: Alignment.centerRight, child: control),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;
  final double width;
  final bool enabled;

  const _Field({
    required this.controller,
    this.prefix,
    this.suffix,
    this.width = 116,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: TextBox(
        controller: controller,
        enabled: enabled,
        prefix: prefix == null ? null : _FieldAffix(prefix!),
        suffix: suffix == null ? null : _FieldAffix(suffix!),
        textAlign: TextAlign.right,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        decoration: WidgetStatePropertyAll(
          BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class _FieldAffix extends StatelessWidget {
  final String text;

  const _FieldAffix(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Select extends StatelessWidget {
  final String value;
  final List<String> values;
  final ValueChanged<String>? onChanged;
  final double width;

  const _Select({
    required this.value,
    required this.values,
    required this.onChanged,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 32,
      child: ComboBox<String>(
        value: value,
        items: values
            .map(
              (item) => ComboBoxItem(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged?.call(next);
              },
      ),
    );
  }
}

class _TimeZoneBadge extends StatelessWidget {
  const _TimeZoneBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'UTC+7',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final String code;
  final String message;
  final bool triggered;
  final String severity;

  const _RuleTile({
    required this.code,
    required this.message,
    required this.triggered,
    required this.severity,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final color = triggered
        ? (severity == 'critical' ? AppColors.danger : AppColors.warning)
        : AppColors.success;
    final title = _localizedRuleTitle(strings, code);
    final detail = _localizedRuleMessage(strings, code, message);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              triggered ? FluentIcons.cancel : FluentIcons.check_mark,
              size: 9,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _localizedRuleTitle(AppStrings strings, String code) {
  final english = switch (code) {
    'max_daily_loss' => 'Max daily loss reached',
    'max_daily_profit' => 'Max daily profit reached',
    'max_trades_per_day' => 'Too many trades today',
    'risk_per_trade' => 'Risk too high',
    'high_impact_news' => 'High impact news window',
    'revenge_trading' => 'Revenge trading pattern',
    'rule_break_count' => 'Rule break count',
    'mt5_autotrading_disabled' => 'MT5 AutoTrading is off',
    _ => _titleCase(code.replaceAll('_', ' ')),
  };
  if (!strings.isVietnamese) return english;
  return switch (code) {
    'max_daily_loss' => 'Cham lo toi da ngay',
    'max_daily_profit' => 'Cham lai toi da ngay',
    'max_trades_per_day' => 'Qua nhieu lenh hom nay',
    'risk_per_trade' => 'Rui ro moi lenh qua cao',
    'high_impact_news' => 'Khung tin tac dong manh',
    'revenge_trading' => 'Dau hieu revenge trading',
    'rule_break_count' => 'So rule dang vi pham',
    'mt5_autotrading_disabled' => 'MT5 AutoTrading dang tat',
    _ => english,
  };
}

String _localizedRuleMessage(AppStrings strings, String code, String message) {
  if (!strings.isVietnamese) return message;

  final numbers = RegExp(r'-?\d+(?:\.\d+)?').allMatches(message).toList();
  String numberAt(int index, String fallback) {
    if (index >= numbers.length) return fallback;
    return numbers[index].group(0) ?? fallback;
  }

  return switch (code) {
    'max_daily_loss' =>
      'PnL ngay ${numberAt(0, '-')} da cham muc lo toi da ${numberAt(1, '-')}.',
    'max_daily_profit' =>
      'PnL ngay ${numberAt(0, '-')} da cham muc lai toi da ${numberAt(1, '-')}.',
    'max_trades_per_day' =>
      '${numberAt(0, '0')} lenh hom nay; gioi han toi da la ${numberAt(1, '-')}.',
    'risk_per_trade' =>
      '${numberAt(0, '0')} lenh vuot rui ro moi lenh ${numberAt(1, '-')}.',
    'high_impact_news' =>
      '${numberAt(0, '0')} tin do dang nam trong khung chan tin.',
    'revenge_trading' => 'Khong phat hien mau revenge trading.',
    'rule_break_count' => '${numberAt(0, '0')} rule chua duoc xu ly.',
    'mt5_autotrading_disabled' =>
      'Bat Algo Trading trong MT5 de bo chan co the dong lenh bi tu choi.',
    _ => message,
  };
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

class _EmptyRules extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        strings.isVietnamese
            ? 'Chua tai kiem tra truc tiep. Hay khoi dong backend hoac lam moi trang.'
            : 'No live checks loaded yet. Start the backend or refresh this page.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.info, size: 13, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _OutlineAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? AppColors.surfaceAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onTap == null
                ? AppColors.textSecondary.withValues(alpha: 0.55)
                : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? AppColors.primary.withValues(alpha: 0.55)
              : AppColors.primary,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 15, color: AppColors.textSecondary),
      ),
    );
  }
}

class _BlockBanner extends StatelessWidget {
  final Map<String, dynamic>? status;

  const _BlockBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final block = status?['block_state'] as Map<String, dynamic>?;
    if (block == null) return const SizedBox.shrink();
    final active = block['active'] as bool? ?? false;
    if (!active) return const SizedBox.shrink();

    final isFullDay = block['full_day_block'] as bool? ?? false;
    final remaining = (block['remaining_seconds'] as num?)?.toInt() ?? 0;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    final countdown = isFullDay
        ? 'Until next trading day'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    final triggeredBy = block['triggered_by'] as List<dynamic>? ?? [];
    final triggerInfo = triggeredBy.isNotEmpty
        ? triggeredBy.map((e) => e.toString()).join(', ')
        : 'Rule violation';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFullDay ? FluentIcons.blocked : FluentIcons.clock,
            size: 15,
            color: isFullDay ? AppColors.danger : AppColors.warning,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFullDay ? 'Trading blocked for the day' : 'Trading blocked temporarily',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isFullDay ? AppColors.danger : AppColors.warning,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '$triggerInfo — $countdown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
