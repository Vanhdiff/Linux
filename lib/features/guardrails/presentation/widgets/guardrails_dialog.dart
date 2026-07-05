import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/guardrails_remote_datasource.dart';

Future<bool?> showGuardrailsDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const GuardrailsDialog(),
  );
}

class GuardrailsDialog extends StatefulWidget {
  const GuardrailsDialog({super.key});

  @override
  State<GuardrailsDialog> createState() => _GuardrailsDialogState();
}

class _GuardrailsDialogState extends State<GuardrailsDialog> {
  int get _accountId => ActiveAccountSession.accountId;

  final _remoteDataSource = GuardrailsRemoteDataSource();
  final _maxTradesController = TextEditingController(text: '3');
  final _maxDailyLossController = TextEditingController(text: '1000');
  final _maxDailyProfitController = TextEditingController(text: '5000');
  final _fixedRiskController = TextEditingController(text: '0.5');
  final _windowStartController = TextEditingController(text: '07:00');
  final _windowEndController = TextEditingController(text: '10:00');
  final _newsMinutesController = TextEditingController(text: '15');

  String _newsBlockMode = 'Before and After';
  bool _loading = true;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _maxTradesController.dispose();
    _maxDailyLossController.dispose();
    _maxDailyProfitController.dispose();
    _fixedRiskController.dispose();
    _windowStartController.dispose();
    _windowEndController.dispose();
    _newsMinutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 820),
      style: ContentDialogThemeData(
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 38,
              offset: Offset(0, 18),
            ),
          ],
        ),
      ),
      content: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: AppColors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('Set your Guardrails'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      strings.text(
                        'These are recommended defaults. You can change them later.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.text(
                        'Guardrails will flag actions that break your rules. Trade blocking stays off until you enable it later.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _GuardrailRow(
                label: strings.text('Max trades per day'),
                control: _SmallTextBox(controller: _maxTradesController),
              ),
              _GuardrailRow(
                label: strings.text('Max daily loss'),
                control: _MoneyInput(controller: _maxDailyLossController),
                helper: strings.text('Uses realized PnL.'),
              ),
              _GuardrailRow(
                label: strings.text('Max daily profit'),
                control: _MoneyInput(controller: _maxDailyProfitController),
                helper: strings.text('Uses realized PnL.'),
              ),
              _GuardrailRow(
                label: strings.text('Fixed risk per trade'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SmallTextBox(controller: _fixedRiskController, width: 82),
                    const SizedBox(width: 8),
                    Text(
                      '%',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                helper: strings.text('Let max auto-adjusts to match risk.'),
              ),
              _GuardrailRow(
                label: strings.text('Trading window'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _TimeZoneBadge(width: 96),
                    const SizedBox(width: 8),
                    _SmallTextBox(
                      controller: _windowStartController,
                      width: 76,
                    ),
                    const SizedBox(width: 8),
                    _SmallTextBox(controller: _windowEndController, width: 76),
                  ],
                ),
                helper: strings.text('Lot size auto-adjusts to match risk.'),
              ),
              _GuardrailRow(
                label: strings.text('News block'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DropdownValue(
                      value: _newsBlockMode,
                      values: const [
                        'Before and After',
                        'Before only',
                        'After only',
                      ],
                      onChanged: (value) =>
                          setState(() => _newsBlockMode = value),
                      width: 154,
                    ),
                    const SizedBox(width: 8),
                    _SmallTextBox(
                      controller: _newsMinutesController,
                      width: 64,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'min',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                helper: strings.text(
                  'Only blocks high-impact events relevant to your pinned pairs.',
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: Row(
                  children: [
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        ),
                      ),
                    _TextAction(
                      label: strings.text('Skip for now'),
                      onTap: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                    ),
                    const Spacer(),
                    _SecondaryButton(
                      label: strings.text('Reset defaults'),
                      onTap: _saving ? null : _resetDefaults,
                    ),
                    const SizedBox(width: 10),
                    _PrimaryButton(
                      label: _saving
                          ? strings.text('Saving...')
                          : strings.text('Save guardrails'),
                      icon: FluentIcons.forward,
                      onTap: _saving ? null : _save,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetDefaults() {
    setState(() {
      _maxTradesController.text = '3';
      _maxDailyLossController.text = '1000';
      _maxDailyProfitController.text = '5000';
      _fixedRiskController.text = '0.5';
      _windowStartController.text = '07:00';
      _windowEndController.text = '10:00';
      _newsMinutesController.text = '15';
      _newsBlockMode = 'Before and After';
      _errorMessage = null;
    });
  }

  Future<void> _loadSavedSettings() async {
    try {
      final status = await _remoteDataSource.fetchStatus(accountId: _accountId);
      final settings = status['settings'] as Map<String, dynamic>? ?? {};
      final nested = settings['settings'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _maxTradesController.text =
            '${(settings['max_trades_per_day'] as num?)?.toInt() ?? 3}';
        _maxDailyLossController.text = _moneyText(
          (settings['max_daily_loss'] as num?)?.toDouble() ?? 1000,
        );
        _maxDailyProfitController.text = _moneyText(
          (nested['max_daily_profit'] as num?)?.toDouble() ?? 5000,
        );
        _fixedRiskController.text = _numberText(
          (nested['fixed_risk_percent'] as num?)?.toDouble() ?? 0.5,
        );
        _newsMinutesController.text =
            '${(nested['news_window_minutes_before'] as num?)?.toInt() ?? 15}';
        _newsBlockMode =
            nested['news_block_mode'] as String? ?? 'Before and After';
        _applyWindow(
          settings['trading_window_start'] as String?,
          isStart: true,
        );
        _applyWindow(settings['trading_window_end'] as String?, isStart: false);
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Could not load saved guardrails. Editing local defaults.';
      });
    }
  }

  Future<void> _save() async {
    final maxTrades = int.tryParse(_maxTradesController.text.trim());
    final maxLoss = double.tryParse(_maxDailyLossController.text.trim());
    final maxProfit = double.tryParse(_maxDailyProfitController.text.trim());
    final fixedRisk = double.tryParse(_fixedRiskController.text.trim());
    final newsMinutes = int.tryParse(_newsMinutesController.text.trim());

    if (maxTrades == null ||
        maxLoss == null ||
        maxProfit == null ||
        fixedRisk == null ||
        newsMinutes == null) {
      setState(() => _errorMessage = 'Please enter valid numeric guardrails.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _remoteDataSource.saveSettings(
        accountId: _accountId,
        maxTradesPerDay: maxTrades,
        maxDailyLoss: maxLoss,
        maxDailyProfit: maxProfit,
        fixedRiskPercent: fixedRisk,
        tradingWindowStart: 'UTC+7 ${_windowStartController.text.trim()}',
        tradingWindowEnd: 'UTC+7 ${_windowEndController.text.trim()}',
        newsBlockMode: _newsBlockMode,
        newsWindowMinutes: newsMinutes,
        tradeBlockingEnabled: false,
        blockMaxTrades: true,
        blockMaxDailyLoss: true,
        blockMaxDailyProfit: true,
        blockHighImpactNews: true,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = 'Could not save guardrails: $error';
      });
    }
  }

  void _applyWindow(String? value, {required bool isStart}) {
    if (value == null || value.isEmpty) return;
    final parts = value.split(RegExp(r'\s+'));
    if (parts.length < 2) return;
    if (isStart) {
      _windowStartController.text = parts.last;
    } else {
      _windowEndController.text = parts.last;
    }
  }
}

String _moneyText(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

String _numberText(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
}

class _GuardrailRow extends StatelessWidget {
  final String label;
  final Widget control;
  final String? helper;

  const _GuardrailRow({
    required this.label,
    required this.control,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 7),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 178,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          SizedBox(
            width: 286,
            child: Align(alignment: Alignment.centerLeft, child: control),
          ),
          if (helper != null)
            Expanded(
              child: Text(
                helper!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          _RecommendedBadge(),
          const SizedBox(width: 10),
          Icon(FluentIcons.info, size: 14, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

class _SmallTextBox extends StatelessWidget {
  final TextEditingController controller;
  final double width;

  const _SmallTextBox({required this.controller, this.width = 96});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 30,
      child: TextBox(
        controller: controller,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        decoration: WidgetStatePropertyAll(
          BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class _TimeZoneBadge extends StatelessWidget {
  final double width;

  const _TimeZoneBadge({this.width = 96});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        'UTC+7',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MoneyInput extends StatelessWidget {
  final TextEditingController controller;

  const _MoneyInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          r'$',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        _SmallTextBox(controller: controller, width: 104),
      ],
    );
  }
}

class _DropdownValue extends StatelessWidget {
  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final double width;

  const _DropdownValue({
    required this.value,
    required this.values,
    required this.onChanged,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 30,
      child: ComboBox<String>(
        value: value,
        items: values
            .map((item) => ComboBoxItem<String>(value: item, child: Text(item)))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Recommended',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _TextAction({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? AppColors.primary.withValues(alpha: 0.55)
              : AppColors.primary,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 9),
            Icon(icon, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
