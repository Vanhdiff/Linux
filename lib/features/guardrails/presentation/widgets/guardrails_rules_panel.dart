import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../app/theme/app_colors.dart';
import 'guardrails_status_sections.dart';

class GuardrailsRulesPanel extends StatelessWidget {
  final int accountId;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? mt5BlockerStatus;
  final Map<String, dynamic>? mt5ProtectionStatus;

  const GuardrailsRulesPanel({
    super.key,
    required this.accountId,
    required this.status,
    required this.mt5BlockerStatus,
    required this.mt5ProtectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final checks = status?['checks'] as List<dynamic>? ?? const [];
    final mt5Issue = _mt5TradeBlockerIssue(mt5BlockerStatus, accountId);
    final protectionIssue = _protectionIssue(mt5ProtectionStatus);
    final blockStateIssue = _blockStateIssue(status);
    final tiles = <Widget>[
      if (protectionIssue != null)
        _ProtectionHealthTile(message: protectionIssue),
      if (blockStateIssue != null)
        _RuleTile(
          code: 'active_block_state',
          message: blockStateIssue,
          triggered: true,
          severity: 'critical',
        ),
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

    return GuardrailsPanel(
      title: strings.text('Live rule checks'),
      subtitle: strings.text(
        'Reads local analytics and cached economic news in real time.',
      ),
      child: tiles.isEmpty ? _EmptyRules() : Column(children: tiles),
    );
  }

  String? _protectionIssue(Map<String, dynamic>? status) {
    final level = status?['level'] as String?;
    final reason = status?['reason'] as String? ?? '';
    final ea = status?['ea'] as Map<String, dynamic>?;
    if (level == null || level == 'FULL') return null;
    final eaError = ea?['error'] as String? ?? '';
    final connected = ea?['connected'] as bool? ?? false;
    if (!connected && eaError.isNotEmpty) {
      return 'Protection $level: $eaError. Setup/health warning only, not a trading-rule violation.';
    }
    return 'Protection $level: $reason. Setup/health warning only, not a trading-rule violation.';
  }

  String? _blockStateIssue(Map<String, dynamic>? status) {
    final blockState = status?['block_state'] as Map<String, dynamic>?;
    if (blockState == null || blockState['active'] != true) return null;
    final blockType = blockState['block_type'] as String? ?? 'block';
    final remaining = (blockState['remaining_seconds'] as num?)?.toInt() ?? 0;
    final triggeredBy =
        blockState['triggered_by'] as List<dynamic>? ?? const [];
    final reasons = triggeredBy.isEmpty
        ? 'previous rule violation'
        : triggeredBy.join(', ');
    return 'Active $blockType block from $reasons. Remaining ${remaining}s.';
  }

  String? _mt5TradeBlockerIssue(Map<String, dynamic>? status, int accountId) {
    final account = _runtimeAccountStatus(status, accountId);
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

  Map<String, dynamic>? _runtimeAccountStatus(
    Map<String, dynamic>? status,
    int accountId,
  ) {
    final accounts = status?['accounts'] as Map<String, dynamic>?;
    if (accounts == null || accounts.isEmpty) return null;

    final direct = accounts['$accountId'];
    if (direct is Map<String, dynamic>) return direct;
    if (direct is Map) return Map<String, dynamic>.from(direct);

    if (accounts.length == 1) {
      final only = accounts.values.first;
      if (only is Map<String, dynamic>) return only;
      if (only is Map) return Map<String, dynamic>.from(only);
    }
    return null;
  }
}

class _ProtectionHealthTile extends StatelessWidget {
  final String message;

  const _ProtectionHealthTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.warning,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              FluentIcons.warning,
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
                  'Protection health',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 3,
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
            ? 'Chua tai kiem tra truc tiep. Hay lam moi trang neu du lieu chua hien.'
            : 'No live checks loaded yet. Refresh if data does not appear shortly.',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
