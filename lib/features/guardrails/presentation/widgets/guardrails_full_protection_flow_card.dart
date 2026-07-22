import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import 'guardrails_surface_widgets.dart';

class GuardrailsFullProtectionFlowCard extends StatelessWidget {
  final Map<String, dynamic>? guardrailStatus;
  final Map<String, dynamic>? installerStatus;
  final Map<String, dynamic>? protectionStatus;
  final Map<String, dynamic>? demoReport;
  final Map<String, dynamic>? setupState;
  final bool busy;
  final VoidCallback onRepair;
  final VoidCallback onRefresh;

  const GuardrailsFullProtectionFlowCard({
    super.key,
    required this.guardrailStatus,
    required this.installerStatus,
    required this.protectionStatus,
    required this.demoReport,
    required this.setupState,
    required this.busy,
    required this.onRepair,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final steps = _buildSteps(strings.isVietnamese);
    final completed = steps.where((step) => step.done).length;
    final total = steps.length;
    final full = completed == total;
    final next = steps.where((step) => !step.done).firstOrNull;
    final mt5Ready =
        _stepDone(steps, 'MT5 terminal detected') &&
        _stepDone(steps, 'EA compiled and verified');
    final heartbeatLive = _stepDone(steps, 'EA heartbeat live');
    final blockingReady =
        _stepDone(steps, 'Trade blocking enabled') &&
        _stepDone(steps, 'Backend enforcement loop running');
    final demoReady = _stepDone(steps, 'Real demo timing captured');
    final canRunOneClick = setupState?['can_run_one_click'] as bool? ?? true;
    final setupHeadline = setupState?['headline']?.toString();
    final setupDetail = setupState?['detail']?.toString();
    final color = full
        ? AppColors.success
        : (completed > 0 ? AppColors.warning : AppColors.textSecondary);

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
              Icon(FluentIcons.shield, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  full
                      ? (strings.isVietnamese
                          ? 'Bao ve da san sang'
                          : 'Protection is ready')
                      : (strings.isVietnamese
                          ? 'Ket noi bao ve MT5'
                          : 'Connect MT5 protection'),
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              GuardrailsOutlineAction(
                label: 'Refresh',
                onTap: busy ? null : onRefresh,
              ),
              const SizedBox(width: 8),
              GuardrailsPrimaryAction(
                label: busy ? 'Running...' : 'One-click setup',
                onTap: busy || !canRunOneClick ? null : onRepair,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            full
                ? (strings.isVietnamese
                    ? 'MT5, EA va che do bao ve da ket noi day du.'
                    : 'MT5, EA, and protection are all connected.')
                : (setupHeadline != null && setupDetail != null
                      ? '$setupHeadline. $setupDetail'
                      : strings.isVietnamese
                          ? '$completed/$total muc da xong. Tiep theo: ${next?.help ?? 'lam moi sau khi MT5 cap nhat.'}'
                          : '$completed/$total steps ready. Next: ${next?.help ?? 'refresh after MT5 updates.'}'),
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
              _VerificationPill(label: 'MT5 EA', done: mt5Ready),
              _VerificationPill(label: 'Heartbeat', done: heartbeatLive),
              _VerificationPill(label: 'Blocker', done: blockingReady),
              _VerificationPill(
                label: strings.isVietnamese ? 'Kiem thu demo' : 'Demo proof',
                done: demoReady,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_VerificationStep> _buildSteps(bool isVietnamese) {
    final terminalCount =
        (installerStatus?['terminal_count'] as num?)?.toInt() ?? 0;
    final installedCount =
        (installerStatus?['installed_count'] as num?)?.toInt() ?? 0;
    final compiledCount =
        (installerStatus?['compiled_count'] as num?)?.toInt() ?? 0;
    final sourceExists = installerStatus?['source_exists'] as bool? ?? false;
    final ea = protectionStatus?['ea'] as Map<String, dynamic>?;
    final diagnostics =
        protectionStatus?['diagnostics'] as Map<String, dynamic>?;
    final completion = demoReport?['completion'] as Map<String, dynamic>?;
    final checklist = (demoReport?['checklist'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final backendRunning =
        protectionStatus?['backend_blocker_running'] as bool? ??
        _checklistCompleted(checklist, 'backend_blocker_running');
    final heartbeatOk =
        (ea?['connected'] as bool? ?? false) &&
        !(ea?['stale'] as bool? ?? false);
    final tradeBlockingEnabled =
        guardrailStatus?['trade_blocking_enabled'] as bool? ?? false;
    final protectionFull =
        (protectionStatus?['level']?.toString().toUpperCase() ?? '') == 'FULL';
    final demoComplete =
        completion?['all_required_timestamp_fields_present'] as bool? ?? false;

    return [
      _VerificationStep(
        title: 'Backend status loaded',
        done: guardrailStatus != null,
        help: isVietnamese
            ? 'Mo app va bam lam moi de tai trang thai moi nhat.'
            : 'Start the service and refresh Guardrails.',
      ),
      _VerificationStep(
        title: 'Trade blocking enabled',
        done: tradeBlockingEnabled,
        help: isVietnamese
            ? 'Bat chan giao dich, roi luu gioi han.'
            : 'Enable trade blocking and save your limits.',
      ),
      _VerificationStep(
        title: 'MT5 terminal detected',
        done: terminalCount > 0,
        help: 'Open MetaTrader 5 so TradingDesk can detect the terminal.',
      ),
      _VerificationStep(
        title: 'EA source available',
        done: sourceExists,
        help: 'Restore TradingDeskGuardEA.mq5 in the app package.',
      ),
      _VerificationStep(
        title: 'EA installed to MT5 Experts',
        done: installedCount > 0,
        help: 'Run one-click setup to copy the EA into MT5.',
      ),
      _VerificationStep(
        title: 'EA compiled and verified',
        done: compiledCount > 0,
        help: 'Run one-click setup or compile TradingDeskGuardEA in MetaEditor.',
      ),
      _VerificationStep(
        title: 'EA runtime config written',
        done: diagnostics?['config_file_exists'] as bool? ?? false,
        help: 'Run one-click setup to write ea_config.json.',
      ),
      _VerificationStep(
        title: 'EA heartbeat live',
        done: heartbeatOk,
        help:
            'Attach TradingDeskGuardEA to one MT5 chart and enable Algo Trading.',
      ),
      _VerificationStep(
        title: 'Backend enforcement loop running',
        done: backendRunning,
        help: isVietnamese
            ? 'Giu TradingDesk dang chay de he thong bao ve tiep tuc hoat dong.'
            : 'Keep TradingDesk running so protection can keep working.',
      ),
      _VerificationStep(
        title: 'Protection level FULL',
        done: protectionFull,
        help:
            'Resolve setup or heartbeat warnings until protection reports FULL.',
      ),
      _VerificationStep(
        title: 'Real demo timing captured',
        done: demoComplete,
        help:
            'Run the real MT5 demo validation so all required timestamps are captured.',
      ),
    ];
  }

  static bool _checklistCompleted(
    List<Map<String, dynamic>> checklist,
    String id,
  ) {
    for (final item in checklist) {
      if (item['id'] == id) return item['completed'] as bool? ?? false;
    }
    return false;
  }

  static bool _stepDone(List<_VerificationStep> steps, String title) {
    for (final step in steps) {
      if (step.title == title) return step.done;
    }
    return false;
  }
}

class _VerificationStep {
  final String title;
  final bool done;
  final String help;

  const _VerificationStep({
    required this.title,
    required this.done,
    required this.help,
  });
}

class _VerificationPill extends StatelessWidget {
  final String label;
  final bool done;

  const _VerificationPill({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.success : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? FluentIcons.completed_solid : FluentIcons.circle_ring,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
