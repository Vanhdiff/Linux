import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_colors.dart';
import '../../guardrails_defaults.dart';
import '../../guardrails_form_support.dart';
import '../../data/datasources/guardrails_remote_datasource.dart';
import 'guardrails_form_controls.dart';
import 'guardrails_time_zone_badge.dart';

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

  static final _defaults = GuardrailsFormValues.defaults();
  final _remoteDataSource = GuardrailsRemoteDataSource();
  final _maxTradesController = TextEditingController(
    text: _defaults.maxTradesPerDay,
  );
  final _maxDailyLossController = TextEditingController(
    text: _defaults.maxDailyLoss,
  );
  final _maxDailyProfitController = TextEditingController(
    text: _defaults.maxDailyProfit,
  );
  final _fixedRiskController = TextEditingController(
    text: _defaults.fixedRiskPercent,
  );
  final _windowStartController = TextEditingController(
    text: _defaults.tradingWindowStart,
  );
  final _windowEndController = TextEditingController(
    text: _defaults.tradingWindowEnd,
  );
  final _newsMinutesController = TextEditingController(
    text: _defaults.newsWindowMinutes,
  );

  String _newsBlockMode = _defaults.newsBlockMode;
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
                control: GuardrailsTextField(
                  controller: _maxTradesController,
                  width: 96,
                  height: 30,
                  fontSize: 12,
                  borderRadius: 7,
                ),
              ),
              _GuardrailRow(
                label: strings.text('Max daily loss'),
                control: GuardrailsMoneyInput(controller: _maxDailyLossController),
                helper: strings.text('Uses realized PnL.'),
              ),
              _GuardrailRow(
                label: strings.text('Max daily profit'),
                control: GuardrailsMoneyInput(controller: _maxDailyProfitController),
                helper: strings.text('Uses realized PnL.'),
              ),
              _GuardrailRow(
                label: strings.text('Fixed risk per trade'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GuardrailsTextField(
                      controller: _fixedRiskController,
                      width: 82,
                      height: 30,
                      fontSize: 12,
                      borderRadius: 7,
                    ),
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
                    const GuardrailsTimeZoneBadge(
                      width: 96,
                      height: 30,
                      radius: 7,
                      fontSize: 12,
                    ),
                    const SizedBox(width: 8),
                    GuardrailsTextField(
                      controller: _windowStartController,
                      width: 76,
                      height: 30,
                      fontSize: 12,
                      borderRadius: 7,
                    ),
                    const SizedBox(width: 8),
                    GuardrailsTextField(
                      controller: _windowEndController,
                      width: 76,
                      height: 30,
                      fontSize: 12,
                      borderRadius: 7,
                    ),
                  ],
                ),
                helper: strings.text('Lot size auto-adjusts to match risk.'),
              ),
              _GuardrailRow(
                label: strings.text('News block'),
                control: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GuardrailsSelect(
                      value: _newsBlockMode,
                      values: GuardrailsDefaults.newsBlockModes,
                      onChanged: (value) =>
                          setState(() => _newsBlockMode = value),
                      width: 154,
                      height: 30,
                    ),
                    const SizedBox(width: 8),
                    GuardrailsTextField(
                      controller: _newsMinutesController,
                      width: 64,
                      height: 30,
                      fontSize: 12,
                      borderRadius: 7,
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
    final defaults = GuardrailsFormValues.defaults();
    setState(() {
      _applyFormValues(defaults);
      _errorMessage = null;
    });
  }

  Future<void> _loadSavedSettings() async {
    try {
      final status = await _remoteDataSource.fetchStatus(accountId: _accountId);
      final settings = status['settings'] as Map<String, dynamic>? ?? {};
      if (!mounted) return;
      setState(() {
        _applyFormValues(GuardrailsFormValues.fromSettings(settings));
        _loading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = AppLocalization.of(context).isVietnamese
            ? 'Chua tai duoc gioi han da luu. Tam thoi dung gia tri mac dinh.'
            : 'Could not load saved limits. Editing local defaults.';
      });
    }
  }

  Future<void> _save() async {
    final input = GuardrailsParsedInput.tryParse(
      maxTradesPerDay: _maxTradesController.text,
      maxDailyLoss: _maxDailyLossController.text,
      maxDailyProfit: _maxDailyProfitController.text,
      fixedRiskPercent: _fixedRiskController.text,
      tradingWindowStart: _windowStartController.text,
      tradingWindowEnd: _windowEndController.text,
      newsBlockMode: _newsBlockMode,
      newsWindowMinutes: _newsMinutesController.text,
      tradeBlockingEnabled: false,
      blockHighImpactNews: true,
    );

    if (input == null) {
      setState(() {
        _errorMessage = AppLocalization.of(context).isVietnamese
            ? 'Hay nhap gia tri hop le cho cac gioi han.'
            : 'Please enter valid numbers for your limits.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await _remoteDataSource.saveSettings(
        accountId: _accountId,
        maxTradesPerDay: input.maxTradesPerDay,
        maxDailyLoss: input.maxDailyLoss,
        maxDailyProfit: input.maxDailyProfit,
        fixedRiskPercent: input.fixedRiskPercent,
        tradingWindowStart: input.tradingWindowStart,
        tradingWindowEnd: input.tradingWindowEnd,
        newsBlockMode: input.newsBlockMode,
        newsWindowMinutes: input.newsWindowMinutes,
        tradeBlockingEnabled: input.tradeBlockingEnabled,
        blockMaxTrades: true,
        blockMaxDailyLoss: true,
        blockMaxDailyProfit: true,
        blockHighImpactNews: input.blockHighImpactNews,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage = AppLocalization.of(context).isVietnamese
            ? 'Khong luu duoc gioi han: $error'
            : 'Could not save limits: $error';
      });
    }
  }

  void _applyFormValues(GuardrailsFormValues values) {
    _maxTradesController.text = values.maxTradesPerDay;
    _maxDailyLossController.text = values.maxDailyLoss;
    _maxDailyProfitController.text = values.maxDailyProfit;
    _fixedRiskController.text = values.fixedRiskPercent;
    _windowStartController.text = values.tradingWindowStart;
    _windowEndController.text = values.tradingWindowEnd;
    _newsMinutesController.text = values.newsWindowMinutes;
    _newsBlockMode = values.newsBlockMode;
  }
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
          const GuardrailsRecommendedBadge(),
          const SizedBox(width: 10),
          Icon(FluentIcons.info, size: 14, color: AppColors.textSecondary),
        ],
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
