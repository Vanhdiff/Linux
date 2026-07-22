import 'dart:async';
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import '../../../../app/i18n/app_localization.dart';

import '../../../../app/services/api/api_config.dart';
import '../../../../app/services/api/api_exception.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_colors.dart';
import '../../guardrails_defaults.dart';
import '../../guardrails_form_support.dart';
import '../../data/datasources/guardrails_remote_datasource.dart';
import '../widgets/guardrails_full_protection_flow_card.dart';
import '../widgets/guardrails_form_controls.dart';
import '../widgets/guardrails_mt5_setup_card.dart';
import '../widgets/guardrails_rules_panel.dart';
import '../widgets/guardrails_status_sections.dart';
import '../widgets/guardrails_surface_widgets.dart';
import '../widgets/guardrails_time_zone_badge.dart';

class GuardrailsPage extends StatefulWidget {
  const GuardrailsPage({super.key});

  @override
  State<GuardrailsPage> createState() => _GuardrailsPageState();
}

class _GuardrailsPageState extends State<GuardrailsPage> {
  int get _accountId => ActiveAccountSession.accountId;

  static final _defaults = GuardrailsFormValues.defaults();
  final _remote = GuardrailsRemoteDataSource();
  final _maxTradesController = TextEditingController(
    text: _defaults.maxTradesPerDay,
  );
  final _maxDailyLossController = TextEditingController(
    text: _defaults.maxDailyLoss,
  );
  final _maxDailyProfitController = TextEditingController(
    text: _defaults.maxDailyProfit,
  );
  final _riskController = TextEditingController(
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
  Timer? _mt5SetupPollTimer;

  Map<String, dynamic>? _status;
  Map<String, dynamic>? _mt5BlockerStatus;
  Map<String, dynamic>? _mt5ProtectionStatus;
  Map<String, dynamic>? _mt5EaInstallStatus;
  Map<String, dynamic>? _mt5EaSetupReport;
  Map<String, dynamic>? _mt5DemoHarnessReport;
  String _newsMode = _defaults.newsBlockMode;
  bool _tradeBlockingEnabled = false;
  bool _blockHighImpactNews = true;
  bool _loading = true;
  bool _saving = false;
  bool _repairingEa = false;
  bool _installingEa = false;
  bool _compilingEa = false;
  bool _refreshingMt5Setup = false;
  bool _showMt5SetupDetails = false;
  bool _mt5ReadyNoticeShown = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _startMt5SetupPolling();
    _loadStatus();
  }

  @override
  void dispose() {
    _mt5SetupPollTimer?.cancel();
    _maxTradesController.dispose();
    _maxDailyLossController.dispose();
    _maxDailyProfitController.dispose();
    _riskController.dispose();
    _windowStartController.dispose();
    _windowEndController.dispose();
    _newsMinutesController.dispose();
    _remote.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 22.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final stackPanels = contentWidth < 1320;
        final pageWidth = contentWidth < 0 ? 0.0 : contentWidth;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            horizontalPadding,
            22,
            horizontalPadding,
            24,
          ),
          child: SizedBox(
            width: pageWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GuardrailsHeader(
                  status: _status,
                  loading: _loading,
                  onRefresh: _loadStatus,
                ),
                const SizedBox(height: 18),
                GuardrailsStatusStrip(
                  status: _status,
                  protectionStatus: _mt5ProtectionStatus,
                ),
                const SizedBox(height: 14),
                _BlockBanner(status: _status),
                const SizedBox(height: 16),
                if (stackPanels) ...[
                  _buildSettingsPanel(),
                  const SizedBox(height: 16),
                  GuardrailsRulesPanel(
                    accountId: _accountId,
                    status: _status,
                    mt5BlockerStatus: _mt5BlockerStatus,
                    mt5ProtectionStatus: _mt5ProtectionStatus,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: _buildSettingsPanel()),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 9,
                        child: GuardrailsRulesPanel(
                          accountId: _accountId,
                          status: _status,
                          mt5BlockerStatus: _mt5BlockerStatus,
                          mt5ProtectionStatus: _mt5ProtectionStatus,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsPanel() {
    final strings = AppLocalization.of(context);
    final hardLocked = _guardrailsHardLocked;
    final lockMessage = _guardrailLockMessage;
    return GuardrailsPanel(
      title: strings.text('Trade blocking rules'),
      subtitle: strings.text(
        'Guardrails can block app/EA trade execution automatically once enabled.',
      ),
      child: Column(
        children: [
          GuardrailsFullProtectionFlowCard(
            guardrailStatus: _status,
            installerStatus: _mt5EaInstallStatus,
            protectionStatus: _mt5ProtectionStatus,
            demoReport: _mt5DemoHarnessReport,
            setupState:
                _mt5EaSetupReport?['one_click_setup']
                    as Map<String, dynamic>?,
            busy: _repairingEa || _installingEa || _compilingEa,
            onRepair: _repairEa,
            onRefresh: _loadStatus,
          ),
          const SizedBox(height: 12),
          GuardrailsSettingRow(
            icon: FluentIcons.lock,
            title: strings.text('Enable trade blocking'),
            description: strings.text(
              'Blocks new orders when an active limit is reached',
            ),
            control: ToggleSwitch(
              checked: _tradeBlockingEnabled,
              onChanged: hardLocked
                  ? null
                  : (value) => setState(() => _tradeBlockingEnabled = value),
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.number_field,
            title: strings.text('Max trades per day'),
            description: strings.text(
              'Stop overtrading by limiting completed trades',
            ),
            control: GuardrailsTextField(
              controller: _maxTradesController,
              suffix: 'trades',
              enabled: !hardLocked,
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.money,
            title: strings.text('Max daily loss'),
            description: strings.text(
              'Uses realized P&L from normalized trades',
            ),
            control: GuardrailsTextField(
              controller: _maxDailyLossController,
              prefix: r'$',
              enabled: !hardLocked,
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.savings,
            title: strings.text('Max daily profit'),
            description: strings.text(
              'Locks in discipline once the target is reached',
            ),
            control: GuardrailsTextField(
              controller: _maxDailyProfitController,
              prefix: r'$',
              enabled: !hardLocked,
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.speed_high,
            title: strings.text('Fixed risk per trade'),
            description: strings.text(
              'Stored for position sizing and risk warnings',
            ),
            control: GuardrailsTextField(
              controller: _riskController,
              suffix: '%',
              enabled: !hardLocked,
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.clock,
            title: strings.text('Trading window'),
            description: strings.text(
              'Used for local warnings outside planned sessions',
            ),
            control: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const GuardrailsTimeZoneBadge(),
                GuardrailsTextField(
                  controller: _windowStartController,
                  width: 64,
                  enabled: !hardLocked,
                ),
                GuardrailsTextField(
                  controller: _windowEndController,
                  width: 64,
                  enabled: !hardLocked,
                ),
              ],
            ),
          ),
          GuardrailsSettingRow(
            icon: FluentIcons.news,
            title: strings.text('High-impact news block'),
            description: strings.text(
              'Blocks red news only - 15 min before & after - yellow allowed',
            ),
            control: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ToggleSwitch(
                  checked: _blockHighImpactNews,
                  onChanged: hardLocked
                      ? null
                      : (value) => setState(() => _blockHighImpactNews = value),
                ),
                GuardrailsSelect(
                  value: _newsMode,
                  values: GuardrailsDefaults.newsBlockModes,
                  width: 150,
                  onChanged: hardLocked
                      ? null
                      : (value) => setState(() => _newsMode = value),
                ),
                GuardrailsTextField(
                  controller: _newsMinutesController,
                  width: 56,
                  suffix: 'm',
                  enabled: !hardLocked,
                ),
              ],
            ),
          ),
          if (lockMessage != null) ...[
            const SizedBox(height: 12),
            GuardrailsNotice(text: lockMessage),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 12),
            GuardrailsNotice(text: _notice!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              GuardrailsOutlineAction(
                label: strings.text('Reset defaults'),
                onTap: hardLocked ? null : _resetDefaults,
              ),
              const Spacer(),
              GuardrailsPrimaryAction(
                label: hardLocked
                    ? strings.text('Locked')
                    : (_saving
                          ? strings.text('Saving...')
                          : strings.text('Save guardrails')),
                onTap: _saving || hardLocked ? null : _save,
              ),
            ],
          ),
          const SizedBox(height: 14),
          GuardrailsEaInstallCard(
            status: _mt5EaInstallStatus,
            setupState:
                _mt5EaSetupReport?['one_click_setup']
                    as Map<String, dynamic>?,
            protectionStatus: _mt5ProtectionStatus,
            showDetails: _showMt5SetupDetails,
            repairing: _repairingEa,
            installing: _installingEa,
            compiling: _compilingEa,
            onRepair: _repairEa,
            onInstall: _installEa,
            onCompile: _compileEa,
            onOpenExperts: _openExpertsFolder,
            onCopyBackendUrl: _copyMt5BackendUrl,
            onCopyReport: _copyMt5SetupReport,
            onRefresh: _loadStatus,
            onToggleDetails: () {
              setState(() => _showMt5SetupDetails = !_showMt5SetupDetails);
            },
          ),
        ],
      ),
    );
  }

  bool get _mt5SetupReady {
    final installer = _mt5EaInstallStatus;
    final protection = _mt5ProtectionStatus;
    final ea = protection?['ea'] as Map<String, dynamic>?;
    return ((installer?['terminal_count'] as num?)?.toInt() ?? 0) > 0 &&
        ((installer?['installed_count'] as num?)?.toInt() ?? 0) > 0 &&
        ((installer?['compiled_count'] as num?)?.toInt() ?? 0) > 0 &&
        (installer?['source_exists'] as bool? ?? false) &&
        (ea?['connected'] as bool? ?? false) &&
        !((ea?['stale'] as bool?) ?? false);
  }

  bool get _demoHarnessComplete {
    final completion =
        _mt5DemoHarnessReport?['completion'] as Map<String, dynamic>?;
    return completion?['all_required_timestamp_fields_present'] as bool? ??
        false;
  }

  bool get _fullProtectionVerified =>
      _mt5SetupReady &&
      (_mt5ProtectionStatus?['level']?.toString().toUpperCase() == 'FULL') &&
      _demoHarnessComplete;

  bool get _shouldPollMt5Setup =>
      !_loading &&
      !_repairingEa &&
      !_installingEa &&
      !_compilingEa &&
      !_refreshingMt5Setup &&
      !_fullProtectionVerified;

  void _startMt5SetupPolling() {
    _mt5SetupPollTimer?.cancel();
    _mt5SetupPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_shouldPollMt5Setup) return;
      _refreshMt5SetupStatus();
    });
  }

  Future<void> _refreshMt5SetupStatus() async {
    if (_refreshingMt5Setup || !mounted) return;
    _refreshingMt5Setup = true;
    try {
      final setupReport = await _remote.fetchMt5EaSetupReport(
        accountId: _accountId,
      );
      Map<String, dynamic>? demoHarnessReport;
      Map<String, dynamic>? blockerStatus;
      try {
        blockerStatus = await _remote.fetchMt5TradeBlockerStatus();
      } catch (_) {
        blockerStatus = _mt5BlockerStatus;
      }
      try {
        demoHarnessReport = await _remote.fetchMt5DemoHarnessReport(
          accountId: _accountId,
        );
      } catch (_) {
        demoHarnessReport = _mt5DemoHarnessReport;
      }
      if (!mounted) return;
      final wasReady = _mt5SetupReady;
      final nextInstaller = setupReport['installer'] as Map<String, dynamic>?;
      final nextProtection = setupReport['protection'] as Map<String, dynamic>?;
      final nextEa = nextProtection?['ea'] as Map<String, dynamic>?;
      final nowReady =
          ((nextInstaller?['terminal_count'] as num?)?.toInt() ?? 0) > 0 &&
          ((nextInstaller?['installed_count'] as num?)?.toInt() ?? 0) > 0 &&
          ((nextInstaller?['compiled_count'] as num?)?.toInt() ?? 0) > 0 &&
          (nextInstaller?['source_exists'] as bool? ?? false) &&
          (nextEa?['connected'] as bool? ?? false) &&
          !((nextEa?['stale'] as bool?) ?? false);
      setState(() {
        _mt5EaInstallStatus = nextInstaller;
        _mt5EaSetupReport = setupReport;
        _mt5ProtectionStatus = nextProtection;
        _mt5BlockerStatus = blockerStatus;
        _mt5DemoHarnessReport = demoHarnessReport;
        if (nowReady && !wasReady && !_mt5ReadyNoticeShown) {
          _notice = AppLocalization.of(context).isVietnamese
              ? 'Da nhan heartbeat tu EA. MT5 va che do bao ve da ket noi xong.'
              : 'EA heartbeat detected. MT5 protection is now connected and ready.';
          _mt5ReadyNoticeShown = true;
        } else if (!nowReady) {
          _mt5ReadyNoticeShown = false;
        }
      });
    } catch (_) {
      // Keep silent during background polling to avoid noisy notices.
    } finally {
      _refreshingMt5Setup = false;
    }
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loading = true;
      _notice = null;
    });

    try {
      final status = await _remote.fetchStatus(accountId: _accountId);
      Map<String, dynamic>? blockerStatus;
      Map<String, dynamic>? protectionStatus;
      Map<String, dynamic>? eaInstallStatus;
      Map<String, dynamic>? demoHarnessReport;
      try {
        blockerStatus = await _remote.fetchMt5TradeBlockerStatus();
      } catch (_) {
        blockerStatus = null;
      }
      try {
        final setupReport = await _remote.fetchMt5EaSetupReport(
          accountId: _accountId,
        );
        protectionStatus = setupReport['protection'] as Map<String, dynamic>?;
        eaInstallStatus = setupReport['installer'] as Map<String, dynamic>?;
        _mt5EaSetupReport = setupReport;
        demoHarnessReport = await _remote.fetchMt5DemoHarnessReport(
          accountId: _accountId,
        );
      } catch (_) {
        try {
          protectionStatus = await _remote.fetchMt5ProtectionStatus(
            accountId: _accountId,
          );
        } catch (_) {
          protectionStatus = null;
        }
        try {
          eaInstallStatus = await _remote.fetchMt5EaInstallStatus();
        } catch (_) {
          eaInstallStatus = null;
        }
        _mt5EaSetupReport = null;
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _mt5BlockerStatus = blockerStatus;
        _mt5ProtectionStatus = protectionStatus;
        _mt5EaInstallStatus = eaInstallStatus;
        _mt5DemoHarnessReport = demoHarnessReport;
        _mt5ReadyNoticeShown = _mt5SetupReady;
        _applySettings(status['settings'] as Map<String, dynamic>?);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Dich vu dang khoi dong. Tam thoi app van dung cac gia tri mac dinh de ban tiep tuc thao tac.'
            : 'Trading service is starting - recommended local defaults are available while data loads.';
      });
    }
  }

  Future<void> _openExpertsFolder() async {
    try {
      await _remote.openMt5ExpertsFolder();
      if (!mounted) return;
      setState(() => _notice = AppLocalization.of(context).isVietnamese
          ? 'Da mo thu muc MT5 Experts.'
          : 'Opened MT5 Experts folder.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong mo duoc thu muc Experts: ${error is ApiException ? error.message : error}'
            : 'Could not open Experts folder: ${error is ApiException ? error.message : error}';
      });
    }
  }

  Future<void> _installEa() async {
    setState(() {
      _installingEa = true;
      _notice = null;
    });

    try {
      final installResult = await _remote.installMt5Ea();
      final setupReport = await _remote.fetchMt5EaSetupReport(
        accountId: _accountId,
      );
      Map<String, dynamic>? demoHarnessReport;
      try {
        demoHarnessReport = await _remote.fetchMt5DemoHarnessReport(
          accountId: _accountId,
        );
      } catch (_) {
        demoHarnessReport = _mt5DemoHarnessReport;
      }
      if (!mounted) return;
      final compiled = installResult['compiled'] as bool? ?? false;
      final verified = installResult['verified'] as bool? ?? false;
      final issue = _extractEaActionIssue(installResult);
      setState(() {
        _mt5EaSetupReport = setupReport;
        _mt5EaInstallStatus = setupReport['installer'] as Map<String, dynamic>?;
        _mt5ProtectionStatus =
            setupReport['protection'] as Map<String, dynamic>?;
        _mt5DemoHarnessReport = demoHarnessReport;
        _installingEa = false;
        _notice = compiled && verified
            ? (AppLocalization.of(context).isVietnamese
                ? 'EA da duoc cai va compile xong. Hay gan TradingDeskGuardEA vao 1 chart roi bat Algo Trading.'
                : 'EA installed, compiled, and verified. Attach TradingDeskGuardEA to one chart, then enable Algo Trading.')
            : (issue == null
                  ? (AppLocalization.of(context).isVietnamese
                      ? 'EA da duoc copy, nhung compile/xac nhan chua xong. Hay mo thu muc Experts hoac chay lai Cai EA.'
                      : 'EA copied, but compile/verify did not complete. Open Experts folder or rerun Install EA.')
                  : (AppLocalization.of(context).isVietnamese
                      ? 'EA da duoc copy, nhung compile/xac nhan chua xong: $issue'
                      : 'EA copied, but compile/verify did not complete: $issue'));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _installingEa = false;
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong cai duoc EA: ${error is ApiException ? error.message : error}'
            : 'Could not install EA: ${error is ApiException ? error.message : error}';
      });
    }
  }

  Future<void> _repairEa() async {
    setState(() {
      _repairingEa = true;
      _notice = null;
    });

    try {
      final repairResult = await _remote.repairMt5Ea(
        accountId: _accountId,
        backendBaseUrl: ApiConfig.baseUrl,
      );
      final setupReport = await _remote.fetchMt5EaSetupReport(
        accountId: _accountId,
      );
      Map<String, dynamic>? demoHarnessReport;
      try {
        demoHarnessReport = await _remote.fetchMt5DemoHarnessReport(
          accountId: _accountId,
        );
      } catch (_) {
        demoHarnessReport = _mt5DemoHarnessReport;
      }
      if (!mounted) return;
      final repaired = repairResult['repaired'] as bool? ?? false;
      final issue = _extractEaActionIssue(repairResult);
      final setupState =
          repairResult['setup_state'] as Map<String, dynamic>? ??
          setupReport['one_click_setup'] as Map<String, dynamic>?;
      final nextAction = setupState?['detail']?.toString();
      setState(() {
        _mt5EaSetupReport = setupReport;
        _mt5EaInstallStatus = setupReport['installer'] as Map<String, dynamic>?;
        _mt5ProtectionStatus =
            setupReport['protection'] as Map<String, dynamic>?;
        _mt5DemoHarnessReport = demoHarnessReport;
        _repairingEa = false;
        _notice = repaired
            ? (AppLocalization.of(context).isVietnamese
                ? 'Thiet lap 1 lan bam da chay xong. Neu heartbeat chua len, hay gan EA vao 1 chart va bat Algo Trading trong MT5.'
                : 'One-click setup completed on the backend. If heartbeat is not live yet, attach the EA to one chart and enable Algo Trading in MT5.')
            : (issue != null
                  ? (AppLocalization.of(context).isVietnamese
                      ? 'Thiet lap 1 lan bam can xu ly them: $issue'
                      : 'One-click setup needs attention: $issue')
                  : (AppLocalization.of(context).isVietnamese
                      ? 'Thiet lap 1 lan bam con thieu 1 buoc: ${nextAction ?? 'xem bao cao thiet lap MT5.'}'
                      : 'One-click setup needs one more step: ${nextAction ?? 'review MT5 setup report.'}'));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _repairingEa = false;
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong the sua thiet lap EA: ${error is ApiException ? error.message : error}'
            : 'Could not repair EA setup: ${error is ApiException ? error.message : error}';
      });
    }
  }

  Future<void> _compileEa() async {
    setState(() {
      _compilingEa = true;
      _notice = null;
    });

    try {
      final compileResult = await _remote.compileMt5Ea();
      final setupReport = await _remote.fetchMt5EaSetupReport(
        accountId: _accountId,
      );
      Map<String, dynamic>? demoHarnessReport;
      try {
        demoHarnessReport = await _remote.fetchMt5DemoHarnessReport(
          accountId: _accountId,
        );
      } catch (_) {
        demoHarnessReport = _mt5DemoHarnessReport;
      }
      if (!mounted) return;
      final compiled = compileResult['compiled'] as bool? ?? false;
      final verified = compileResult['verified'] as bool? ?? false;
      final issue = _extractEaActionIssue(compileResult);
      setState(() {
        _mt5EaInstallStatus = setupReport['installer'] as Map<String, dynamic>?;
        _mt5EaSetupReport = setupReport;
        _mt5ProtectionStatus =
            setupReport['protection'] as Map<String, dynamic>?;
        _mt5DemoHarnessReport = demoHarnessReport;
        _compilingEa = false;
        _notice = compiled && verified
            ? (AppLocalization.of(context).isVietnamese
                ? 'EA da compile xong. Hay gan TradingDeskGuardEA vao 1 chart roi bat Algo Trading.'
                : 'EA compiled and verified. Attach TradingDeskGuardEA to one chart, then enable Algo Trading.')
            : (issue == null
                  ? (AppLocalization.of(context).isVietnamese
                      ? 'Compile chua hoan tat gon gang. Hay sao chep bao cao de xem them chan doan MetaEditor/log.'
                      : 'Compile did not complete cleanly. Copy Report to inspect MetaEditor/log diagnostics.')
                  : (AppLocalization.of(context).isVietnamese
                      ? 'Compile chua hoan tat gon gang: $issue'
                      : 'Compile did not complete cleanly: $issue'));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _compilingEa = false;
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong compile duoc EA: ${error is ApiException ? error.message : error}'
            : 'Could not compile EA: ${error is ApiException ? error.message : error}';
      });
    }
  }

  String? _extractEaActionIssue(Map<String, dynamic> result) {
    final directError = result['error']?.toString();
    if (directError != null && directError.trim().isNotEmpty) {
      return directError.trim();
    }

    final errors = result['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first?.toString();
      if (first != null && first.trim().isNotEmpty) {
        return first.trim();
      }
    }

    final targetIssue = _extractIssueFromTargetList(result['targets']);
    if (targetIssue != null) return targetIssue;

    final compileResults = result['compile_results'];
    if (compileResults is List) {
      for (final entry in compileResults) {
        if (entry is Map<String, dynamic>) {
          final nestedIssue = _extractEaActionIssue(entry);
          if (nestedIssue != null) return nestedIssue;
        } else if (entry is Map) {
          final nestedIssue = _extractEaActionIssue(
            Map<String, dynamic>.from(entry),
          );
          if (nestedIssue != null) return nestedIssue;
        }
      }
    }

    final installResult = result['install'];
    if (installResult is Map<String, dynamic>) {
      final nestedIssue = _extractEaActionIssue(installResult);
      if (nestedIssue != null) return nestedIssue;
    } else if (installResult is Map) {
      final nestedIssue = _extractEaActionIssue(
        Map<String, dynamic>.from(installResult),
      );
      if (nestedIssue != null) return nestedIssue;
    }

    return null;
  }

  String? _extractIssueFromTargetList(Object? targets) {
    if (targets is! List) return null;
    for (final target in targets) {
      final map = switch (target) {
        Map<String, dynamic>() => target,
        Map() => Map<String, dynamic>.from(target),
        _ => null,
      };
      if (map == null) continue;
      final targetError = map['error']?.toString();
      if (targetError != null && targetError.trim().isNotEmpty) {
        return targetError.trim();
      }
      final tail = map['compile_log_tail'];
      if (tail is List && tail.isNotEmpty) {
        final last = tail.last?.toString();
        if (last != null && last.trim().isNotEmpty) {
          return last.trim();
        }
      }
    }
    return null;
  }

  Future<void> _copyMt5SetupReport() async {
    try {
      final report = await _remote.fetchMt5EaSetupReport(accountId: _accountId);
      const encoder = JsonEncoder.withIndent('  ');
      await Clipboard.setData(ClipboardData(text: encoder.convert(report)));
      if (!mounted) return;
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Da sao chep bao cao thiet lap MT5.'
            : 'MT5 setup report copied.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong sao chep duoc bao cao thiet lap MT5: ${error is ApiException ? error.message : error}'
            : 'Could not copy MT5 setup report: ${error is ApiException ? error.message : error}';
      });
    }
  }

  Future<void> _copyMt5BackendUrl() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ApiConfig.baseUrl));
      if (!mounted) return;
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Da sao chep URL ket noi. Trong MT5: Tools -> Options -> Expert Advisors -> cho phep WebRequest cho URL nay.'
            : 'Copied connection URL. In MT5: Tools -> Options -> Expert Advisors -> Allow WebRequest for listed URL.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Khong sao chep duoc URL ket noi: $error'
            : 'Could not copy connection URL: $error';
      });
    }
  }

  Future<void> _save() async {
    final strings = AppLocalization.of(context);
    final input = GuardrailsParsedInput.tryParse(
      maxTradesPerDay: _maxTradesController.text,
      maxDailyLoss: _maxDailyLossController.text,
      maxDailyProfit: _maxDailyProfitController.text,
      fixedRiskPercent: _riskController.text,
      tradingWindowStart: _windowStartController.text,
      tradingWindowEnd: _windowEndController.text,
      newsBlockMode: _newsMode,
      newsWindowMinutes: _newsMinutesController.text,
      tradeBlockingEnabled: _tradeBlockingEnabled,
      blockHighImpactNews: _blockHighImpactNews,
    );

    if (input == null) {
      setState(() {
        _notice = AppLocalization.of(context).isVietnamese
            ? 'Hay nhap gia tri hop le cho cac gioi han.'
            : 'Please enter valid numbers for your limits.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _notice = null;
    });

    try {
      await _remote.saveSettings(
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
      await _loadStatus();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = _tradeBlockingEnabled
            ? strings.text(
                'Guardrails saved. MT5 trade blocker will enforce active limits.',
              )
            : strings.text(
                'Guardrails saved. Trade blocking is currently off.',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice = _saveErrorMessage(error);
      });
    }
  }

  bool get _guardrailsHardLocked {
    final lock = _status?['guardrail_lock'] as Map<String, dynamic>?;
    return lock?['hard_locked'] as bool? ?? false;
  }

  String? get _guardrailLockMessage {
    final lock = _status?['guardrail_lock'] as Map<String, dynamic>?;
    if (lock == null) return null;
    final message = lock['message'] as String?;
    if (message == null || message.isEmpty) return null;
    final hardLocked = lock['hard_locked'] as bool? ?? false;
    final tightenOnly = lock['tighten_only'] as bool? ?? false;
    if (!hardLocked && !tightenOnly) return null;
    return message;
  }

  String _saveErrorMessage(Object error) {
    if (error is ApiException) {
      try {
        final body = jsonDecode(error.message);
        if (body is Map<String, dynamic>) {
          final detail = body['detail'];
          if (detail is String && detail.isNotEmpty) return detail;
        }
      } catch (_) {
        // Fall through to the raw exception message.
      }
      return error.message;
    }
    return AppLocalization.of(context).isVietnamese
        ? 'Khong luu duoc gioi han. Dich vu co the dang khoi dong hoac tam thoi mat ket noi.'
        : 'Could not save limits. The service may still be starting or temporarily offline.';
  }

  void _resetDefaults() {
    final defaults = GuardrailsFormValues.defaults();
    setState(() {
      _applyFormValues(defaults);
      _notice = null;
    });
  }

  void _applySettings(Map<String, dynamic>? settings) {
    _applyFormValues(
      GuardrailsFormValues.fromSettings(settings, includePendingUpdates: true),
    );
  }

  void _applyFormValues(GuardrailsFormValues values) {
    _maxTradesController.text = values.maxTradesPerDay;
    _maxDailyLossController.text = values.maxDailyLoss;
    _maxDailyProfitController.text = values.maxDailyProfit;
    _riskController.text = values.fixedRiskPercent;
    _windowStartController.text = values.tradingWindowStart;
    _windowEndController.text = values.tradingWindowEnd;
    _newsMinutesController.text = values.newsWindowMinutes;
    _newsMode = values.newsBlockMode;
    _tradeBlockingEnabled = values.tradeBlockingEnabled;
    _blockHighImpactNews = values.blockHighImpactNews;
  }
}

class _BlockBanner extends StatelessWidget {
  final Map<String, dynamic>? status;

  const _BlockBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final block = status?['block_state'] as Map<String, dynamic>?;
    if (block == null) return const SizedBox.shrink();
    final active = block['active'] as bool? ?? false;
    if (!active) return const SizedBox.shrink();

    final isFullDay = block['full_day_block'] as bool? ?? false;
    final remaining = (block['remaining_seconds'] as num?)?.toInt() ?? 0;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    final countdown = isFullDay
        ? 'Until next trading day'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    final triggeredBy = block['triggered_by'] as List<dynamic>? ?? [];
    final triggerInfo = triggeredBy.isNotEmpty
        ? triggeredBy.map((e) => e.toString()).join(', ')
        : 'Rule violation';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(
          alpha: 0.10,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(
            alpha: 0.20,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isFullDay ? FluentIcons.blocked : FluentIcons.clock,
            size: 15,
            color: isFullDay ? AppColors.danger : AppColors.warning,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFullDay
                      ? 'Trading blocked for the day'
                      : 'Trading blocked temporarily',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isFullDay ? AppColors.danger : AppColors.warning,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '$triggerInfo - $countdown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: (isFullDay ? AppColors.danger : AppColors.warning)
                        .withValues(alpha: 0.8),
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
