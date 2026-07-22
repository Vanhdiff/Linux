import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import 'guardrails_surface_widgets.dart';

class GuardrailsHeader extends StatelessWidget {
  final Map<String, dynamic>? status;
  final bool loading;
  final VoidCallback onRefresh;

  const GuardrailsHeader({
    super.key,
    required this.status,
    required this.loading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final summary = status?['summary'] as Map<String, dynamic>? ?? {};
    final critical = (summary['critical_count'] as num?)?.toInt() ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 12,
          spacing: 12,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: compact ? constraints.maxWidth : 640,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.text('Account protection'),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.text(
                      'Automated limits that keep your trading inside the plan and enforce protection directly on MT5.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (critical > 0)
                  _AttentionPill(
                    text: '$critical ${strings.text('critical rule needs attention')}',
                  ),
                if (critical > 0) const SizedBox(width: 10),
                GuardrailsIconAction(
                  icon: loading ? FluentIcons.sync : FluentIcons.refresh,
                  onTap: onRefresh,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class GuardrailsStatusStrip extends StatelessWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? protectionStatus;

  const GuardrailsStatusStrip({
    super.key,
    required this.status,
    required this.protectionStatus,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final summary = status?['summary'] as Map<String, dynamic>? ?? {};
    final triggered = (summary['triggered_count'] as num?)?.toInt() ?? 0;
    final critical = (summary['critical_count'] as num?)?.toInt() ?? 0;
    final protectionLevel = protectionStatus?['level'] as String? ?? 'UNKNOWN';
    final blocking = status?['trade_blocking_enabled'] as bool? ?? false;
    final blocked = status?['trade_blocked'] as bool? ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 900
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        final wideCardWidth = constraints.maxWidth >= 1280
            ? (constraints.maxWidth - 36) / 4
            : cardWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: wideCardWidth,
              child: _StatusCard(
                icon: FluentIcons.lock,
                label: strings.text('Trade blocking'),
                value: blocked
                    ? strings.text('Blocked')
                    : (blocking ? strings.text('Ready') : strings.text('Off')),
                color: blocked
                    ? AppColors.danger
                    : (blocking ? AppColors.success : AppColors.warning),
              ),
            ),
            SizedBox(
              width: wideCardWidth,
              child: _StatusCard(
                icon: FluentIcons.shield,
                label: strings.text('Protection level'),
                value: strings.text(protectionLevelLabel(protectionLevel)),
                color: protectionLevelColor(protectionLevel),
              ),
            ),
            SizedBox(
              width: wideCardWidth,
              child: _StatusCard(
                icon: FluentIcons.warning,
                label: strings.text('Triggered rules'),
                value: '$triggered ${strings.text('active')}',
                color: triggered > 0 ? AppColors.warning : AppColors.success,
              ),
            ),
            SizedBox(
              width: wideCardWidth,
              child: _StatusCard(
                icon: FluentIcons.error_badge,
                label: strings.text('Critical'),
                value: '$critical ${strings.text('critical')}',
                color: critical > 0 ? AppColors.danger : AppColors.success,
              ),
            ),
          ],
        );
      },
    );
  }
}

class GuardrailsPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const GuardrailsPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

String protectionLevelLabel(String value) {
  switch (value.toUpperCase()) {
    case 'FULL':
      return 'Full protection';
    case 'DEGRADED':
      return 'Degraded';
    case 'OFF':
      return 'Off';
    default:
      return 'Unknown';
  }
}

Color protectionLevelColor(String value) {
  switch (value.toUpperCase()) {
    case 'FULL':
      return AppColors.success;
    case 'DEGRADED':
      return AppColors.warning;
    case 'OFF':
      return AppColors.danger;
    default:
      return AppColors.textSecondary;
  }
}

class _AttentionPill extends StatelessWidget {
  final String text;

  const _AttentionPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
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
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
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
