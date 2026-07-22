import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
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
    final strings = AppLocalization.of(context);
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
            ? (strings.isVietnamese
                ? 'Bao ve da ket noi'
                : 'Protection is connected')
            : (terminalCount > 0
                  ? (strings.isVietnamese
                      ? 'Ket noi bao ve voi MT5'
                      : 'Connect MT5 protection')
                  : (strings.isVietnamese
                      ? 'Mo MT5 de bat dau'
                      : 'Open MT5 to start')));
    final detail =
        setupState?['detail']?.toString() ??
        (sourceExists
            ? (strings.isVietnamese
                ? 'Da cai $installedCount/$terminalCount EA, da compile $compiledCount/$terminalCount.'
                : '$installedCount/$terminalCount EA installed, $compiledCount/$terminalCount compiled.')
            : (strings.isVietnamese
                ? 'Khong tim thay file EA trong bo cai cua app.'
                : 'EA file is missing from the app package.'));
    final canRunOneClick =
        setupState?['can_run_one_click'] as bool? ??
        (sourceExists && terminalCount > 0);
    final primaryAction =
        setupState?['primary_action']?.toString() ??
        (canRunOneClick
            ? (strings.isVietnamese ? 'Thiet lap 1 lan bam' : 'Run one-click setup')
            : (strings.isVietnamese ? 'Xem huong dan' : 'Review setup'));
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
      isVietnamese: strings.isVietnamese,
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
                label: showDetails
                    ? (strings.isVietnamese ? 'An chi tiet' : 'Hide details')
                    : (strings.isVietnamese ? 'Xem chi tiet' : 'Show details'),
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
                  label: repairing
                      ? (strings.isVietnamese ? 'Dang thiet lap...' : 'Running setup...')
                      : primaryAction,
                  onTap: busy || !canRunOneClick ? null : onRepair,
                ),
              GuardrailsOutlineAction(
                label: setupCode == 'ready'
                    ? (strings.isVietnamese ? 'Lam moi' : 'Refresh')
                    : (strings.isVietnamese ? 'Kiem tra lai' : 'Check again'),
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
                label: _stepLabel(setupCode, strings.isVietnamese),
                color: color,
              ),
            ],
            const SizedBox(height: 10),
            GuardrailsNextStepPanel(
              title: ready
                  ? (strings.isVietnamese ? 'San sang' : 'Ready')
                  : (strings.isVietnamese ? 'Buoc tiep theo' : 'What to do next'),
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
                isVietnamese: strings.isVietnamese,
              ),
              ready: ready,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                GuardrailsOutlineAction(
                  label: strings.isVietnamese ? 'Sao chep chan doan' : 'Copy diagnostics',
                  onTap: busy ? null : onCopyReport,
                ),
                if (showInstall)
                  GuardrailsOutlineAction(
                    label: installing
                        ? (strings.isVietnamese ? 'Dang cai...' : 'Installing...')
                        : (strings.isVietnamese ? 'Cai EA' : 'Install EA'),
                    onTap: busy ? null : onInstall,
                  ),
                if (showCompile)
                  GuardrailsOutlineAction(
                    label: compiling
                        ? (strings.isVietnamese ? 'Dang compile...' : 'Compiling...')
                        : (strings.isVietnamese ? 'Compile' : 'Compile'),
                    onTap: busy ? null : onCompile,
                  ),
                if (showOpenFolder)
                  GuardrailsOutlineAction(
                    label: strings.isVietnamese ? 'Mo thu muc MT5' : 'Open MT5 folder',
                    onTap: busy ? null : onOpenExperts,
                  ),
                if (showCopyUrl)
                  GuardrailsOutlineAction(
                    label: strings.isVietnamese ? 'Sao chep URL' : 'Copy URL',
                    onTap: busy ? null : onCopyBackendUrl,
                  ),
              ],
            ),
            if (showAdvanced) ...[
              const SizedBox(height: 8),
              Text(
                strings.isVietnamese
                    ? 'Chi hien cong cu ky thuat khi no thuc su can cho buoc hien tai.'
                    : 'Technical tools appear only when they can help with the current step.',
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
    required bool isVietnamese,
  }) {
    if (ready) {
      return isVietnamese
          ? 'MT5, EA va he thong bao ve da san sang.'
          : 'MT5, EA heartbeat, and backend protection are all ready.';
    }
    if (setupDetail != null && setupDetail.trim().isNotEmpty) {
      return setupDetail.trim();
    }
    if (terminalCount == 0) {
      return isVietnamese
          ? 'Hay mo MetaTrader 5 de app nhan dien duoc terminal cua ban.'
          : 'Open MetaTrader 5 so TradingDesk can detect your terminal.';
    }
    if (!sourceExists) {
      return isVietnamese
          ? 'Khong tim thay file nguon EA trong bo cai cua app.'
          : 'The EA source file is missing from the app package.';
    }
    if (compiledCount == 0) {
      return isVietnamese
          ? 'Hay chay thiet lap 1 lan bam de copy va compile TradingDeskGuardEA.'
          : 'Run one-click setup to copy and compile TradingDeskGuardEA.';
    }
    if (!heartbeatOk) {
      return isVietnamese
          ? 'Gan TradingDeskGuardEA vao 1 chart, sau do bat Algo Trading. WebRequest chi can neu ban dung kiem tra truoc khi vao lenh tai $backendUrl.'
          : 'Attach TradingDeskGuardEA to one chart, then enable Algo Trading. WebRequest is only needed for pre-trade validation at $backendUrl.';
    }
    if ((protectionLevel ?? '').toUpperCase() != 'FULL') {
      return isVietnamese
          ? 'MT5 da ket noi. TradingDesk dang hoan tat nhung buoc kiem tra cuoi.'
          : 'MT5 is connected. TradingDesk is still finishing the final protection checks.';
    }
    if (setupCode == 'ready') {
      return isVietnamese
          ? 'Bao ve da ket noi va san sang.'
          : 'Protection is connected and ready.';
    }
    return isVietnamese
        ? 'Lam moi sau khi MT5 cap nhat de tiep tuc qua trinh thiet lap.'
        : 'Refresh after MT5 updates to continue the setup flow.';
  }

  static String _stepLabel(String code, bool isVietnamese) {
    switch (code) {
      case 'open_mt5':
        return isVietnamese ? 'Buoc 1: Mo MT5' : 'Step 1: Open MT5';
      case 'missing_ea_source':
        return isVietnamese
            ? 'Buoc 1: Khoi phuc goi EA'
            : 'Step 1: Restore EA package';
      case 'install_required':
        return isVietnamese ? 'Buoc 2: Copy EA vao MT5' : 'Step 2: Copy EA to MT5';
      case 'compile_required':
        return isVietnamese ? 'Buoc 3: Compile EA' : 'Step 3: Compile EA';
      case 'config_required':
        return isVietnamese
            ? 'Buoc 4: Ghi cau hinh chay'
            : 'Step 4: Write runtime config';
      case 'attach_ea':
        return isVietnamese
            ? 'Buoc 5: Gan EA vao chart'
            : 'Step 5: Attach EA to chart';
      case 'heartbeat_pending':
        return isVietnamese
            ? 'Buoc 6: Bat Algo Trading'
            : 'Step 6: Enable Algo Trading';
      case 'backend_waiting':
        return isVietnamese
            ? 'Buoc 7: Cho he thong bao ve ket noi'
            : 'Step 7: Wait for protection';
      case 'protection_syncing':
        return isVietnamese
            ? 'Buoc 8: Xac nhan bao ve'
            : 'Step 8: Verify protection';
      case 'ready':
        return isVietnamese ? 'Bao ve san sang' : 'Protection ready';
      default:
        return isVietnamese ? 'Buoc thiet lap' : 'Setup step';
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
    required bool isVietnamese,
    String? setupCode,
    String? setupDetail,
  }) {
    if (setupDetail != null &&
        setupDetail.trim().isNotEmpty &&
        setupCode != 'ready') {
      final steps = <String>[setupDetail.trim()];
      if (setupCode == 'heartbeat_pending') {
        steps.add(
          isVietnamese
              ? 'Neu dung kiem tra truoc khi vao lenh, hay cho phep WebRequest voi $backendUrl.'
              : 'For pre-trade validation, allow WebRequest for $backendUrl.',
        );
      }
      return steps;
    }
    if (terminalCount == 0) {
      return [
        isVietnamese
            ? 'Mo MetaTrader 5 de TradingDesk nhan dien duoc.'
            : 'Open MetaTrader 5 so TradingDesk can detect it.',
      ];
    }
    if (!sourceExists) {
      return [
        isVietnamese
            ? 'Khoi phuc file TradingDeskGuardEA.mq5 trong bo cai cua app.'
            : 'Restore TradingDeskGuardEA.mq5 in the app package.',
      ];
    }
    if (installedCount == 0) {
      return [
        isVietnamese
            ? 'Chay thiet lap 1 lan bam de copy EA vao MT5.'
            : 'Run one-click setup to copy the EA into MT5.',
      ];
    }
    if (compiledCount == 0) {
      return [
        metaeditorExists
            ? (isVietnamese
                ? 'Bam Compile de tao file TradingDeskGuardEA.ex5.'
                : 'Click Compile to generate TradingDeskGuardEA.ex5.')
            : (isVietnamese
                ? 'Hay cai dat day du MT5, sau do compile EA trong MetaEditor.'
                : 'Install MT5 completely, then compile the EA in MetaEditor.'),
      ];
    }
    if (!heartbeatOk) {
      return [
        isVietnamese
            ? 'Gan TradingDeskGuardEA vao 1 chart va bat Algo Trading.'
            : 'Attach TradingDeskGuardEA to one chart and enable Algo Trading.',
        isVietnamese
            ? 'Neu dung kiem tra truoc khi vao lenh, hay cho phep WebRequest voi $backendUrl.'
            : 'For pre-trade validation, allow WebRequest for $backendUrl.',
      ];
    }
    if ((protectionLevel ?? '').toUpperCase() != 'FULL') {
      return [
        isVietnamese
            ? 'Giu MT5 mo trong khi TradingDesk hoan tat cac buoc kiem tra bao ve.'
            : 'Keep MT5 open while TradingDesk finishes protection checks.',
      ];
    }
    return [
      isVietnamese
          ? 'Che do chan giao dich gio da co the thuc thi cac gioi han dang bat.'
          : 'Trade blocking can now enforce active guardrails.',
    ];
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
