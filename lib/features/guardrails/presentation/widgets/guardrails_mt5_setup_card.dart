import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/services/api/api_config.dart';
import '../../../../app/theme/app_colors.dart';
import 'guardrails_mt5_setup_support.dart';
import 'guardrails_surface_widgets.dart';

class GuardrailsEaInstallCard extends StatelessWidget {
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? setupState;
  final Map<String, dynamic>? protectionStatus;
  final bool showDetails;
  final bool repairing;
  final bool installing;
  final bool compiling;
  final VoidCallback onRepair;
  final VoidCallback onInstall;
  final VoidCallback onCompile;
  final VoidCallback onOpenExperts;
  final VoidCallback onCopyBackendUrl;
  final VoidCallback onCopyReport;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDetails;

  const GuardrailsEaInstallCard({
    super.key,
    required this.status,
    required this.setupState,
    required this.protectionStatus,
    required this.showDetails,
    required this.repairing,
    required this.installing,
    required this.compiling,
    required this.onRepair,
    required this.onInstall,
    required this.onCompile,
    required this.onOpenExperts,
    required this.onCopyBackendUrl,
    required this.onCopyReport,
    required this.onRefresh,
    required this.onToggleDetails,
  });

  @override
  Widget build(BuildContext context) {
    final terminalCount = (status?['terminal_count'] as num?)?.toInt() ?? 0;
    final installedCount = (status?['installed_count'] as num?)?.toInt() ?? 0;
    final compiledCount = (status?['compiled_count'] as num?)?.toInt() ?? 0;
    final sourceExists = status?['source_exists'] as bool? ?? false;
    final metaeditorExists = status?['metaeditor_exists'] as bool? ?? false;
    final ea = protectionStatus?['ea'] as Map<String, dynamic>?;
    final backendUrl = ApiConfig.baseUrl;
    final eaConnected = ea?['connected'] as bool? ?? false;
    final eaStale = ea?['stale'] as bool? ?? false;
    final heartbeatOk = eaConnected && !eaStale;
    final busy = repairing || installing || compiling;
    final ready = setupState?['ready'] as bool? ?? false;
    final setupCode = setupState?['code']?.toString();
    final headline =
        setupState?['headline']?.toString() ??
        (ready
            ? 'Protection is connected'
            : (terminalCount > 0
                  ? 'Connect MT5 protection'
                  : 'Open MT5 to start'));
    final detail =
        setupState?['detail']?.toString() ??
        (sourceExists
            ? '$installedCount/$terminalCount EA installed, $compiledCount/$terminalCount compiled.'
            : 'EA file is missing from the app package.');
    final canRunOneClick =
        setupState?['can_run_one_click'] as bool? ??
        (sourceExists && terminalCount > 0);
    final primaryAction =
        setupState?['primary_action']?.toString() ??
        (canRunOneClick ? 'Run one-click setup' : 'Review setup');
    final waitingForMt5 = setupCode == 'attach_ea' || setupCode == 'heartbeat_pending';
    final showInstall = terminalCount > 0 && sourceExists && installedCount == 0;
    final showCompile =
        terminalCount > 0 &&
        sourceExists &&
        installedCount > 0 &&
        compiledCount == 0;
    final showOpenFolder = terminalCount > 0 && waitingForMt5;
    final showCopyUrl = waitingForMt5;
    final showAdvanced = showInstall || showCompile || showOpenFolder || showCopyUrl;
    final color = ready
        ? AppColors.success
        : (terminalCount > 0 ? AppColors.warning : AppColors.danger);
    final summaryText = _buildSummaryText(
      ready: ready,
      setupCode: setupCode,
      setupDetail: setupState?['detail']?.toString(),
      heartbeatOk: heartbeatOk,
      backendUrl: backendUrl,
      terminalCount: terminalCount,
      sourceExists: sourceExists,
      compiledCount: compiledCount,
      protectionLevel: protectionStatus?['level'] as String?,
    );
    final showPrimaryAction = !ready && canRunOneClick;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(FluentIcons.shield, size: 17, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GuardrailsOutlineAction(
                label: showDetails ? 'Hide details' : 'Show details',
                onTap: onToggleDetails,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SetupSummaryBanner(
            color: color,
            ready: ready,
            text: summaryText,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (showPrimaryAction)
                GuardrailsPrimaryAction(
                  label: repairing ? 'Running setup...' : primaryAction,
                  onTap: busy || !canRunOneClick ? null : onRepair,
                ),
              GuardrailsOutlineAction(
                label: setupCode == 'ready' ? 'Refresh' : 'Check again',
                onTap: busy ? null : onRefresh,
              ),
            ],
          ),
          if (showDetails) ...[
            const SizedBox(height: 12),
            GuardrailsProtectionBadges(
              protectionLevel: protectionStatus?['level'] as String?,
              heartbeatOk: heartbeatOk,
              stale: eaStale,
              connected: eaConnected,
              terminalCount: terminalCount,
              compiledCount: compiledCount,
            ),
            if (setupCode != null) ...[
              const SizedBox(height: 10),
              _SetupStepBadge(
                label: _stepLabel(setupCode),
                color: color,
              ),
            ],
            const SizedBox(height: 10),
            GuardrailsNextStepPanel(
              title: ready ? 'Ready' : 'What to do next',
              steps: _buildNextSteps(
                terminalCount: terminalCount,
                sourceExists: sourceExists,
                installedCount: installedCount,
                compiledCount: compiledCount,
                metaeditorExists: metaeditorExists,
                heartbeatOk: heartbeatOk,
                backendUrl: backendUrl,
                protectionLevel: protectionStatus?['level'] as String?,
                setupCode: setupCode,
                setupDetail: setupState?['detail']?.toString(),
              ),
              ready: ready,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GuardrailsOutlineAction(
                  label: 'Copy diagnostics',
                  onTap: busy ? null : onCopyReport,
                ),
                if (showInstall)
                  GuardrailsOutlineAction(
                    label: installing ? 'Installing...' : 'Install EA',
                    onTap: busy ? null : onInstall,
                  ),
                if (showCompile)
                  GuardrailsOutlineAction(
                    label: compiling ? 'Compiling...' : 'Compile',
                    onTap: busy ? null : onCompile,
                  ),
                if (showOpenFolder)
                  GuardrailsOutlineAction(
                    label: 'Open MT5 folder',
                    onTap: busy ? null : onOpenExperts,
                  ),
                if (showCopyUrl)
                  GuardrailsOutlineAction(
                    label: 'Copy URL',
                    onTap: busy ? null : onCopyBackendUrl,
                  ),
              ],
            ),
            if (showAdvanced) ...[
              const SizedBox(height: 8),
              Text(
                'Technical tools appear only when they can help with the current step.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  static String _buildSummaryText({
    required bool ready,
    required String? setupCode,
    required String? setupDetail,
    required bool heartbeatOk,
    required String backendUrl,
    required int terminalCount,
    required bool sourceExists,
    required int compiledCount,
    required String? protectionLevel,
  }) {
    if (ready) {
      return 'MT5, EA heartbeat, and backend protection are all ready.';
    }
    if (setupDetail != null && setupDetail.trim().isNotEmpty) {
      return setupDetail.trim();
    }
    if (terminalCount == 0) {
      return 'Open MetaTrader 5 so TradingDesk can detect your terminal.';
    }
    if (!sourceExists) {
      return 'The EA source file is missing from the app package.';
    }
    if (compiledCount == 0) {
      return 'Run one-click setup to copy and compile TradingDeskGuardEA.';
    }
    if (!heartbeatOk) {
      return 'Attach TradingDeskGuardEA to one chart, then enable Algo Trading. WebRequest is only needed for pre-trade validation at $backendUrl.';
    }
    if ((protectionLevel ?? '').toUpperCase() != 'FULL') {
      return 'MT5 is connected. TradingDesk is still finishing the final protection checks.';
    }
    if (setupCode == 'ready') {
      return 'Protection is connected and ready.';
    }
    return 'Refresh after MT5 updates to continue the setup flow.';
  }

  static String _stepLabel(String code) {
    switch (code) {
      case 'open_mt5':
        return 'Step 1: Open MT5';
      case 'missing_ea_source':
        return 'Step 1: Restore EA package';
      case 'install_required':
        return 'Step 2: Copy EA to MT5';
      case 'compile_required':
        return 'Step 3: Compile EA';
      case 'config_required':
        return 'Step 4: Write runtime config';
      case 'attach_ea':
        return 'Step 5: Attach EA to chart';
      case 'heartbeat_pending':
        return 'Step 6: Enable Algo Trading';
      case 'backend_waiting':
        return 'Step 7: Wait for backend protection';
      case 'protection_syncing':
        return 'Step 8: Verify protection';
      case 'ready':
        return 'Protection ready';
      default:
        return 'Setup step';
    }
  }

  static List<String> _buildNextSteps({
    required int terminalCount,
    required bool sourceExists,
    required int installedCount,
    required int compiledCount,
    required bool metaeditorExists,
    required bool heartbeatOk,
    required String backendUrl,
    required String? protectionLevel,
    String? setupCode,
    String? setupDetail,
  }) {
    if (setupDetail != null &&
        setupDetail.trim().isNotEmpty &&
        setupCode != 'ready') {
      final steps = <String>[setupDetail.trim()];
      if (setupCode == 'heartbeat_pending') {
        steps.add(
          'For pre-trade validation, allow WebRequest for $backendUrl.',
        );
      }
      return steps;
    }
    if (terminalCount == 0) {
      return const ['Open MetaTrader 5 so TradingDesk can detect it.'];
    }
    if (!sourceExists) {
      return const ['Restore TradingDeskGuardEA.mq5 in the app package.'];
    }
    if (installedCount == 0) {
      return const ['Run one-click setup to copy the EA into MT5.'];
    }
    if (compiledCount == 0) {
      return [
        metaeditorExists
            ? 'Click Compile to generate TradingDeskGuardEA.ex5.'
            : 'Install MT5 completely, then compile the EA in MetaEditor.',
      ];
    }
    if (!heartbeatOk) {
      return [
        'Attach TradingDeskGuardEA to one chart and enable Algo Trading.',
        'For pre-trade validation, allow WebRequest for $backendUrl.',
      ];
    }
    if ((protectionLevel ?? '').toUpperCase() != 'FULL') {
      return const [
        'Keep MT5 open while TradingDesk finishes protection checks.',
      ];
    }
    return const ['Trade blocking can now enforce active guardrails.'];
  }
}

class _SetupSummaryBanner extends StatelessWidget {
  final Color color;
  final bool ready;
  final String text;

  const _SetupSummaryBanner({
    required this.color,
    required this.ready,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? FluentIcons.completed_solid : FluentIcons.info,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupStepBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SetupStepBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
