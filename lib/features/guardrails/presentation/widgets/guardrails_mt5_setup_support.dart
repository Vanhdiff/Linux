import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'guardrails_status_sections.dart';

class GuardrailsNextStepPanel extends StatelessWidget {
  final String title;
  final List<String> steps;
  final bool ready;

  const GuardrailsNextStepPanel({
    super.key,
    required this.title,
    required this.steps,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    final tone = ready ? AppColors.success : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tone,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ready
                        ? FluentIcons.completed_solid
                        : FluentIcons.chevron_right_small,
                    size: 11,
                    color: tone,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      step,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
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

class GuardrailsProtectionBadges extends StatelessWidget {
  final String? protectionLevel;
  final bool heartbeatOk;
  final bool stale;
  final bool connected;
  final int terminalCount;
  final int compiledCount;

  const GuardrailsProtectionBadges({
    super.key,
    required this.protectionLevel,
    required this.heartbeatOk,
    required this.stale,
    required this.connected,
    required this.terminalCount,
    required this.compiledCount,
  });

  @override
  Widget build(BuildContext context) {
    final protection = (protectionLevel ?? 'UNKNOWN').toUpperCase();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatusBadge(
          label: 'Protection',
          value: protection,
          color: protectionLevelColor(protection),
        ),
        _StatusBadge(
          label: 'Heartbeat',
          value: heartbeatOk
              ? 'LIVE'
              : (stale ? 'STALE' : (connected ? 'WAITING' : 'OFFLINE')),
          color: heartbeatOk
              ? AppColors.success
              : (stale ? AppColors.warning : AppColors.danger),
        ),
        _StatusBadge(
          label: 'Terminals',
          value: '$compiledCount/$terminalCount ready',
          color: compiledCount > 0 ? AppColors.primary : AppColors.textSecondary,
        ),
      ],
    );
  }
}

class GuardrailsTerminalTargetsPanel extends StatelessWidget {
  final List<Map<String, dynamic>> targets;

  const GuardrailsTerminalTargetsPanel({super.key, required this.targets});

  @override
  Widget build(BuildContext context) {
    final primaryTerminalId = targets.first['terminal_id']?.toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Detected MT5 terminals',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final target in targets) ...[
            _TerminalTargetRow(
              target: target,
              highlighted: target['terminal_id']?.toString() == primaryTerminalId,
            ),
            if (target != targets.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class GuardrailsDiagnosticsGrid extends StatelessWidget {
  final List<GuardrailsDiagnosticItem> rows;

  const GuardrailsDiagnosticsGrid({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows
          .where((row) => row.value != null && row.value!.trim().isNotEmpty)
          .map((row) => _DiagnosticChip(item: row))
          .toList(),
    );
  }
}

class GuardrailsDiagnosticItem {
  final String label;
  final String? value;
  final String? state;

  const GuardrailsDiagnosticItem({
    required this.label,
    required this.value,
    this.state,
  });
}

class GuardrailsChecklistRow extends StatelessWidget {
  final bool done;
  final String text;

  const GuardrailsChecklistRow({
    super.key,
    required this.done,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        children: [
          Icon(
            done ? FluentIcons.completed_solid : FluentIcons.circle_ring,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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

class _TerminalTargetRow extends StatelessWidget {
  final Map<String, dynamic> target;
  final bool highlighted;

  const _TerminalTargetRow({
    required this.target,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final terminalId = target['terminal_id']?.toString() ?? 'Unknown';
    final expertsDir = target['experts_dir']?.toString() ?? '';
    final installed = target['installed'] as bool? ?? false;
    final compiled = target['compiled'] as bool? ?? false;
    final stateColor = compiled
        ? AppColors.success
        : (installed ? AppColors.warning : AppColors.textSecondary);
    final stateLabel = compiled
        ? 'compiled'
        : (installed ? 'copied only' : 'not installed');
    final accent = compiled
        ? AppColors.success
        : (installed ? AppColors.warning : AppColors.textSecondary);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? accent.withValues(alpha: 0.10)
            : AppColors.surfaceAlt.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted
              ? accent.withValues(alpha: 0.28)
              : AppColors.border.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  terminalId,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (highlighted) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.24)),
                  ),
                  child: Text(
                    'priority',
                    style: TextStyle(
                      color: accent,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              Text(
                stateLabel,
                style: TextStyle(
                  color: stateColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            expertsDir,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MiniStatePill(
                label: installed ? 'EA copied' : 'EA missing',
                done: installed,
              ),
              _MiniStatePill(
                label: compiled ? '.ex5 ready' : '.ex5 missing',
                done: compiled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatePill extends StatelessWidget {
  final String label;
  final bool done;

  const _MiniStatePill({
    required this.label,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DiagnosticChip extends StatelessWidget {
  final GuardrailsDiagnosticItem item;

  const _DiagnosticChip({required this.item});

  @override
  Widget build(BuildContext context) {
    final stateColor = switch (item.state) {
      'exists' => AppColors.success,
      'missing' => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (item.state != null)
                Text(
                  item.state!,
                  style: TextStyle(
                    color: stateColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.value!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
