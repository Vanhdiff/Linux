import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'guardrails_surface_widgets.dart';

class GuardrailsDemoHarnessCard extends StatelessWidget {
  final Map<String, dynamic>? report;
  final bool loading;
  final bool showDetails;
  final VoidCallback onRefresh;
  final VoidCallback onCopyReport;
  final VoidCallback onToggleDetails;

  const GuardrailsDemoHarnessCard({
    super.key,
    required this.report,
    required this.loading,
    required this.showDetails,
    required this.onRefresh,
    required this.onCopyReport,
    required this.onToggleDetails,
  });

  @override
  Widget build(BuildContext context) {
    final completion = report?['completion'] as Map<String, dynamic>?;
    final allTimestampsPresent =
        completion?['all_required_timestamp_fields_present'] as bool? ?? false;
    final checklist = (report?['checklist'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final completedCount = checklist
        .where((item) => item['completed'] as bool? ?? false)
        .length;
    final totalCount = checklist.length;
    final timing = report?['timing_audit'] as Map<String, dynamic>?;
    final durations = timing?['durations_ms'] as Map<String, dynamic>?;
    final targets = timing?['targets'] as Map<String, dynamic>?;
    final backendWithinTarget =
        targets?['backend_reaction_within_target'] as bool? ?? false;
    final color = allTimestampsPresent
        ? AppColors.success
        : (completedCount > 0 ? AppColors.warning : AppColors.textSecondary);
    final title = allTimestampsPresent
        ? 'Demo protection proof ready'
        : 'Demo protection proof pending';
    final subtitle = totalCount == 0
        ? 'No demo harness report loaded yet.'
        : '$completedCount/$totalCount checks passed. Backend target: reaction under 500ms.';
    final measuredCount = [
      durations?['backend_reaction_ms'],
      durations?['block_persistence_ms'],
      durations?['ea_close_reaction_ms'],
      durations?['broker_execution_ms'],
    ].whereType<num>().length;
    final proofColor = allTimestampsPresent
        ? AppColors.success
        : (measuredCount > 0 ? AppColors.warning : AppColors.textSecondary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FluentIcons.test_beaker, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loading ? 'Loading real demo validation...' : title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              GuardrailsOutlineAction(
                label: showDetails ? 'Hide details' : 'Show details',
                onTap: onToggleDetails,
              ),
              const SizedBox(width: 8),
              GuardrailsOutlineAction(
                label: 'Refresh',
                onTap: loading ? null : onRefresh,
              ),
              const SizedBox(width: 8),
              GuardrailsOutlineAction(
                label: 'Copy proof',
                onTap: loading || report == null ? null : onCopyReport,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DemoMetricPill(
                label: 'Proof status',
                value: allTimestampsPresent
                    ? 'Ready'
                    : (measuredCount > 0 ? 'In progress' : 'Not started'),
                color: proofColor,
              ),
              _DemoMetricPill(
                label: 'Backend reaction',
                value: _durationLabel(durations?['backend_reaction_ms']),
                color: backendWithinTarget
                    ? AppColors.success
                    : AppColors.warning,
              ),
              _DemoMetricPill(
                label: 'Timestamps',
                value: totalCount == 0
                    ? 'No report'
                    : '$completedCount/$totalCount',
                color: allTimestampsPresent
                    ? AppColors.success
                    : AppColors.textSecondary,
              ),
            ],
          ),
          if (showDetails) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DemoMetricPill(
                  label: 'Block persistence',
                  value: _durationLabel(durations?['block_persistence_ms']),
                  color: _durationColor(durations?['block_persistence_ms']),
                ),
                _DemoMetricPill(
                  label: 'EA close reaction',
                  value: _durationLabel(durations?['ea_close_reaction_ms']),
                  color: _durationColor(durations?['ea_close_reaction_ms']),
                ),
                _DemoMetricPill(
                  label: 'Broker execution',
                  value: _durationLabel(durations?['broker_execution_ms']),
                  color: _durationColor(durations?['broker_execution_ms']),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _durationLabel(Object? value) {
    if (value is num) return '${value.toInt()}ms';
    return 'Not measured';
  }

  static Color _durationColor(Object? value) {
    if (value is! num) return AppColors.textSecondary;
    return value <= 500 ? AppColors.success : AppColors.warning;
  }
}

class _DemoMetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DemoMetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
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
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
