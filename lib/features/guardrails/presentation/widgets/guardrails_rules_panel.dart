import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/i18n/app_strings.dart';
import '../../../../app/theme/app_colors.dart';
import 'guardrails_status_sections.dart';

class GuardrailsRulesPanel extends StatefulWidget {
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
  State<GuardrailsRulesPanel> createState() => _GuardrailsRulesPanelState();
}

class _GuardrailsRulesPanelState extends State<GuardrailsRulesPanel> {
  bool _showPassedChecks = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final checks = widget.status?['checks'] as List<dynamic>? ?? const [];
    final mt5Issue = _mt5TradeBlockerIssue(
      strings,
      widget.mt5BlockerStatus,
      widget.accountId,
    );
    final protectionIssue = _protectionIssue(strings, widget.mt5ProtectionStatus);
    final blockStateIssue = _blockStateIssue(widget.status);
    final parsedChecks = checks
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final triggeredChecks = parsedChecks
        .where((item) => item['triggered'] as bool? ?? false)
        .toList();
    final passedChecks = parsedChecks
        .where((item) => !(item['triggered'] as bool? ?? false))
        .toList();
    final criticalCount = triggeredChecks
        .where((item) => (item['severity'] as String? ?? 'info') == 'critical')
        .length;
    final warningCount = triggeredChecks.length - criticalCount;
    final hasActionItems =
        protectionIssue != null ||
        blockStateIssue != null ||
        mt5Issue != null ||
        triggeredChecks.isNotEmpty;

    final actionTiles = <Widget>[
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
      ...triggeredChecks.map((json) {
        return _RuleTile(
          code: json['rule_code'] as String? ?? 'rule',
          message: json['message'] as String? ?? '',
          triggered: json['triggered'] as bool? ?? false,
          severity: json['severity'] as String? ?? 'info',
        );
      }),
    ];

    return GuardrailsPanel(
      title: strings.isVietnamese
          ? 'Canh bao dang can xu ly'
          : 'What needs attention',
      subtitle: strings.text(
        strings.isVietnamese
            ? 'Chi hien thi cac dieu kien dang anh huong den giao dich va trang thai bao ve hien tai.'
            : 'Shows only the active trading blockers and current protection health.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RulesSummaryStrip(
            triggeredCount: triggeredChecks.length,
            passedCount: passedChecks.length,
            criticalCount: criticalCount,
            warningCount: warningCount,
            hasActionItems: hasActionItems,
          ),
          const SizedBox(height: 10),
          if (actionTiles.isEmpty)
            _QuietStateCard(
              title: strings.isVietnamese
                  ? 'Khong co dieu kien dang chan giao dich'
                  : 'No active trading blockers',
              message: strings.isVietnamese
                  ? 'Cac dieu kien hien tai dang an toan. He thong bao ve san sang xu ly neu co vi pham moi.'
                  : 'Current checks look healthy. Protection is ready to enforce if a new violation appears.',
            )
          else
            Column(children: actionTiles),
          if (passedChecks.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PassedChecksDisclosure(
              count: passedChecks.length,
              open: _showPassedChecks,
              onToggle: () {
                setState(() => _showPassedChecks = !_showPassedChecks);
              },
            ),
            if (_showPassedChecks) ...[
              const SizedBox(height: 8),
              ...passedChecks.map((json) {
                return _RuleTile(
                  code: json['rule_code'] as String? ?? 'rule',
                  message: json['message'] as String? ?? '',
                  triggered: false,
                  severity: json['severity'] as String? ?? 'info',
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  String? _protectionIssue(AppStrings strings, Map<String, dynamic>? status) {
    final level = status?['level'] as String?;
    final reason = status?['reason'] as String? ?? '';
    final ea = status?['ea'] as Map<String, dynamic>?;
    if (level == null || level == 'FULL') return null;
    final eaError = ea?['error'] as String? ?? '';
    final connected = ea?['connected'] as bool? ?? false;
    if (strings.isVietnamese) {
      if (!connected && eaError.isNotEmpty) {
        return 'Bao ve $level: $eaError. Day la canh bao cai dat/ket noi, khong phai vi pham giao dich.';
      }
      return 'Bao ve $level: $reason. Day la canh bao cai dat/ket noi, khong phai vi pham giao dich.';
    }
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

  String? _mt5TradeBlockerIssue(
    AppStrings strings,
    Map<String, dynamic>? status,
    int accountId,
  ) {
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
        if (strings.isVietnamese) {
          return 'MT5 dang tat AutoTrading. Hay bat Algo Trading trong MT5 de he thong co the dong lenh bi tu choi.';
        }
        return 'MT5 AutoTrading is off. Enable Algo Trading in MT5 so the blocker can close rejected trades.';
      }
    }
    final error = action?['error'] as String?;
    if (error != null && error.isNotEmpty) {
      if (strings.isVietnamese) {
        return 'Loi he thong chan lenh MT5: $error';
      }
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

class _RulesSummaryStrip extends StatelessWidget {
  final int triggeredCount;
  final int passedCount;
  final int criticalCount;
  final int warningCount;
  final bool hasActionItems;

  const _RulesSummaryStrip({
    required this.triggeredCount,
    required this.passedCount,
    required this.criticalCount,
    required this.warningCount,
    required this.hasActionItems,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryPill(
          label: strings.isVietnamese ? 'Trang thai' : 'Status',
          value: hasActionItems
              ? (strings.isVietnamese ? 'Can xu ly' : 'Action needed')
              : (strings.isVietnamese ? 'On dinh' : 'Healthy'),
          color: hasActionItems ? AppColors.warning : AppColors.success,
        ),
        if (triggeredCount > 0)
          _SummaryPill(
            label: strings.isVietnamese ? 'Dang kich hoat' : 'Triggered',
            value: '$triggeredCount',
            color: AppColors.danger,
          ),
        if (criticalCount > 0)
          _SummaryPill(
            label: strings.isVietnamese ? 'Critical' : 'Critical',
            value: '$criticalCount',
            color: AppColors.danger,
          ),
        if (warningCount > 0)
          _SummaryPill(
            label: strings.isVietnamese ? 'Canh bao' : 'Warnings',
            value: '$warningCount',
            color: AppColors.warning,
          ),
        if (passedCount > 0)
          _SummaryPill(
            label: strings.isVietnamese ? 'On dinh' : 'Passed',
            value: '$passedCount',
            color: AppColors.success,
          ),
      ],
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietStateCard extends StatelessWidget {
  final String title;
  final String message;

  const _QuietStateCard({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              FluentIcons.check_mark,
              size: 10,
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
                const SizedBox(height: 4),
                Text(
                  message,
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

class _PassedChecksDisclosure extends StatelessWidget {
  final int count;
  final bool open;
  final VoidCallback onToggle;

  const _PassedChecksDisclosure({
    required this.count,
    required this.open,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return GestureDetector(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                open
                    ? (strings.isVietnamese
                        ? 'An $count dieu kien dang on dinh'
                        : 'Hide $count healthy checks')
                    : (strings.isVietnamese
                        ? 'Xem $count dieu kien dang on dinh'
                        : 'Show $count healthy checks'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              open ? FluentIcons.chevron_up : FluentIcons.chevron_down,
              size: 12,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
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
                  AppLocalization.of(context).isVietnamese
                      ? 'Suc khoe protection'
                      : 'Protection health',
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
    'active_block_state' => 'Active block state',
    'max_daily_loss_reached' => 'Max daily loss reached',
    'max_daily_loss' => 'Max daily loss reached',
    'max_daily_profit_reached' => 'Max daily profit reached',
    'max_daily_profit' => 'Max daily profit reached',
    'too_many_trades_today' => 'Too many trades today',
    'max_trades_per_day' => 'Too many trades today',
    'risk_too_high' => 'Risk too high',
    'risk_per_trade' => 'Risk too high',
    'high_impact_news_window' => 'High impact news window',
    'high_impact_news' => 'High impact news window',
    'revenge_trading_pattern' => 'Revenge trading pattern',
    'revenge_trading' => 'Revenge trading pattern',
    'consecutive_losses_pause_active' => 'Consecutive losses pause active',
    'cooling_off_active' => 'Cooling off active',
    'live_averaging_loss' => 'Live averaging loss',
    'live_martingale' => 'Live martingale',
    'rule_break_count' => 'Rule break count',
    'mt5_autotrading_disabled' => 'MT5 AutoTrading is off',
    _ => _titleCase(code.replaceAll('_', ' ')),
  };
  if (!strings.isVietnamese) return english;
  return switch (code) {
    'active_block_state' => 'Trang thai block dang hoat dong',
    'max_daily_loss_reached' => 'Cham lo toi da ngay',
    'max_daily_loss' => 'Cham lo toi da ngay',
    'max_daily_profit_reached' => 'Cham lai toi da ngay',
    'max_daily_profit' => 'Cham lai toi da ngay',
    'too_many_trades_today' => 'Qua nhieu lenh hom nay',
    'max_trades_per_day' => 'Qua nhieu lenh hom nay',
    'risk_too_high' => 'Rui ro moi lenh qua cao',
    'risk_per_trade' => 'Rui ro moi lenh qua cao',
    'high_impact_news_window' => 'Khung tin tac dong manh',
    'high_impact_news' => 'Khung tin tac dong manh',
    'revenge_trading_pattern' => 'Dau hieu revenge trading',
    'revenge_trading' => 'Dau hieu revenge trading',
    'consecutive_losses_pause_active' => 'Tam dung do thua lien tiep',
    'cooling_off_active' => 'Che do cooling off dang bat',
    'live_averaging_loss' => 'Dau hieu averaging loss',
    'live_martingale' => 'Dau hieu martingale',
    'rule_break_count' => 'So dieu kien dang vi pham',
    'mt5_autotrading_disabled' => 'MT5 AutoTrading dang tat',
    _ => english,
  };
}

String _localizedRuleMessage(AppStrings strings, String code, String message) {
  if (!strings.isVietnamese) return message;

  final numbers = RegExp(r'-?\d+(?:\.\d+)?').allMatches(message).toList();
  String numberAt(int index, String fallback) {
    if (index < 0 || index >= numbers.length) return fallback;
    return numbers[index].group(0) ?? fallback;
  }

  final lower = message.toLowerCase();
  return switch (code) {
    'active_block_state' =>
      'Dang co block tam thoi. Ly do: ${_extractBlockReasons(message)}. Con lai ${numberAt(numbers.length - 1, '0')} giay.',
    'max_daily_loss_reached' => lower.contains('has not reached')
        ? 'Closed PnL ${numberAt(0, '-')} va floating PnL ${numberAt(1, '-')} chua cham muc lo toi da ${numberAt(2, '-')}.'
        : 'Closed PnL ${numberAt(0, '-')} va floating PnL ${numberAt(1, '-')} da cham muc lo toi da ${numberAt(2, '-')}.',
    'max_daily_loss' => lower.contains('has not reached')
        ? 'Closed PnL ${numberAt(0, '-')} va floating PnL ${numberAt(1, '-')} chua cham muc lo toi da ${numberAt(2, '-')}.'
        : 'Closed PnL ${numberAt(0, '-')} va floating PnL ${numberAt(1, '-')} da cham muc lo toi da ${numberAt(2, '-')}.',
    'max_daily_profit_reached' => lower.contains('has not reached')
        ? 'PnL ngay ${numberAt(0, '-')} chua cham muc lai toi da ${numberAt(1, '-')}.'
        : 'PnL ngay ${numberAt(0, '-')} da cham muc lai toi da ${numberAt(1, '-')}.',
    'max_daily_profit' => lower.contains('has not reached')
        ? 'PnL ngay ${numberAt(0, '-')} chua cham muc lai toi da ${numberAt(1, '-')}.'
        : 'PnL ngay ${numberAt(0, '-')} da cham muc lai toi da ${numberAt(1, '-')}.',
    'too_many_trades_today' =>
      '${numberAt(0, '0')} lenh hom nay; gioi han toi da la ${numberAt(1, '-')}.',
    'max_trades_per_day' =>
      '${numberAt(0, '0')} lenh hom nay; gioi han toi da la ${numberAt(1, '-')}.',
    'risk_too_high' =>
      '${numberAt(0, '0')} lenh vuot muc rui ro ${numberAt(1, '-')} (${numberAt(2, '-')}% tai khoan); ${numberAt(3, '0')} lenh thieu SL; ${numberAt(4, '0')} lenh thieu risk.',
    'risk_per_trade' =>
      '${numberAt(0, '0')} lenh vuot muc rui ro ${numberAt(1, '-')} (${numberAt(2, '-')}% tai khoan); ${numberAt(3, '0')} lenh thieu SL; ${numberAt(4, '0')} lenh thieu risk.',
    'high_impact_news_window' =>
      '${numberAt(0, '0')} tin do dang nam trong khung chan tin.',
    'high_impact_news' =>
      '${numberAt(0, '0')} tin do dang nam trong khung chan tin.',
    'revenge_trading_pattern' => lower.contains('detected')
        ? '${numberAt(0, '0')} mau revenge trading duoc phat hien trong ${numberAt(1, '0')} phut.'
        : 'Khong phat hien mau revenge trading.',
    'revenge_trading' => lower.contains('detected')
        ? '${numberAt(0, '0')} mau revenge trading duoc phat hien trong ${numberAt(1, '0')} phut.'
        : 'Khong phat hien mau revenge trading.',
    'consecutive_losses_pause_active' => lower.contains('active')
        ? '${numberAt(0, '0')} lenh thua lien tiep dang kich hoat tam dung giao dich den ${_extractIsoTimestamp(message) ?? 'thoi diem quy dinh'}.'
        : 'Khong co tam dung giao dich do thua lien tiep.',
    'cooling_off_active' => lower.contains('no active')
        ? 'Khong co cooling off dang hoat dong.'
        : 'Cooling off dang hoat dong.',
    'live_averaging_loss' => lower.contains('no ')
        ? 'Khong phat hien mau averaging loss dang dien ra.'
        : 'Phat hien dau hieu averaging loss dang dien ra.',
    'live_martingale' => lower.contains('no ')
        ? 'Khong phat hien mau martingale dang dien ra.'
        : 'Phat hien dau hieu martingale dang dien ra.',
    'rule_break_count' => '${numberAt(0, '0')} dieu kien chua duoc xu ly.',
    'mt5_autotrading_disabled' =>
      'Bat Algo Trading trong MT5 de bo chan co the dong lenh bi tu choi.',
    _ => message,
  };
}

String _extractBlockReasons(String message) {
  final fromIndex = message.indexOf('from ');
  final remainingIndex = message.indexOf('. Remaining');
  if (fromIndex == -1) return 'khong ro';
  final start = fromIndex + 5;
  final end = remainingIndex == -1 ? message.length : remainingIndex;
  return message.substring(start, end).trim();
}

String? _extractIsoTimestamp(String message) {
  final match = RegExp(
    r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}',
  ).firstMatch(message);
  return match?.group(0);
}

String _titleCase(String value) {
  if (value.isEmpty) return value;
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
