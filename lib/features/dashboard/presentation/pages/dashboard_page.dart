import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/datasources/dashboard_remote_datasource.dart';
import '../../domain/entities/dashboard_period.dart';
import 'all_trades_page.dart';
import '../models/dashboard_mt5_snapshot.dart';
import '../widgets/dashboard_top_metrics.dart';
import '../widgets/discipline_panel.dart';
import '../widgets/equity_chart.dart';
import '../widgets/recent_trades_table.dart';
import '../widgets/rule_break_panel.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final DashboardRemoteDataSource _dataSource;
  Timer? _refreshTimer;
  Timer? _liveTimer;
  DashboardApiView _dashboard = DashboardApiView.empty();
  DashboardGuardrailStatus? _guardrails;
  DashboardLiveState? _liveState;
  DashboardPeriod _period = DashboardPeriod.day;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _requestInFlight = false;
  bool _liveRequestInFlight = false;
  bool _hasLoadedDashboard = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dataSource = DashboardRemoteDataSource();
    _loadDashboard(showLoading: true);
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (mounted && !_requestInFlight) {
        _loadDashboard(silent: true);
      }
    });
    _liveTimer = Timer.periodic(Duration(milliseconds: 500), (_) {
      if (mounted && !_liveRequestInFlight) {
        _pollLiveState();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _liveTimer?.cancel();
    _dataSource.close();
    super.dispose();
  }

  Future<void> _loadDashboard({
    DashboardPeriod? period,
    bool refreshMt5 = false,
    bool showLoading = false,
    bool silent = false,
  }) async {
    if (_requestInFlight) return;
    final nextPeriod = period ?? _period;
    final periodChanged = nextPeriod != _period;
    final useFullLoading =
        !silent && (showLoading || (!_hasLoadedDashboard && !_isRefreshing));
    _requestInFlight = true;
    if (!silent) {
      setState(() {
        _period = nextPeriod;
        _isLoading = useFullLoading || periodChanged;
        _isRefreshing = !_isLoading;
        _errorMessage = null;
      });
    } else {
      _period = nextPeriod;
    }

    try {
      final dashboard = await _dataSource.getDashboard(
        period: nextPeriod,
        refreshMt5: refreshMt5,
      );
      DashboardGuardrailStatus? guardrails;
      try {
        guardrails = await _dataSource.getGuardrailStatus();
      } catch (_) {
        guardrails = _guardrails;
      }
      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _guardrails = guardrails;
        _hasLoadedDashboard = true;
        _isLoading = false;
        _isRefreshing = false;
        _requestInFlight = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent) {
        _requestInFlight = false;
        return;
      }
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _requestInFlight = false;
        _errorMessage =
            'Trading service is starting. Refresh if data does not appear shortly.';
      });
    }
  }

  Future<void> _pollLiveState() async {
    if (_liveRequestInFlight) return;
    _liveRequestInFlight = true;
    final previousFingerprint = _liveState?.fingerprint;
    final previousTradeId = _liveState?.latestTradeId;
    final previousBlocked = _liveState?.blockState.active ?? false;
    final previousPositionCount = _liveState?.openPositionCount ?? 0;
    try {
      final liveState = await _dataSource.getLiveState();
      if (!mounted) return;
      final hasFingerprintChanged =
          previousFingerprint != null &&
          previousFingerprint.isNotEmpty &&
          previousFingerprint != liveState.fingerprint;
      final latestTradeChanged = previousTradeId != liveState.latestTradeId;
      final blockChanged = previousBlocked != liveState.blockState.active;
      final positionCountChanged =
          previousPositionCount != liveState.openPositionCount;
      setState(() {
        _liveState = liveState;
      });
      if (hasFingerprintChanged &&
          !_requestInFlight &&
          (latestTradeChanged || blockChanged || positionCountChanged)) {
        unawaited(_loadDashboard(silent: true));
      }
    } catch (_) {
      if (!mounted) return;
    } finally {
      _liveRequestInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = 28.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;
        final targetWidth = contentWidth * 0.94;
        final pageWidth = targetWidth < 1180 ? 1180.0 : targetWidth;
        final scrollWidth = pageWidth > contentWidth ? pageWidth : contentWidth;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            18,
            horizontalPadding,
            18,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: scrollWidth,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: pageWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DashboardHeader(
                        isLoading: _isLoading,
                        isRefreshing: _isRefreshing,
                        liveState: _liveState,
                        errorMessage: _errorMessage,
                        onRefresh: () {
                          _loadDashboard(refreshMt5: true);
                        },
                        selectedPeriod: _period,
                        onPeriodChanged: (period) {
                          _loadDashboard(period: period);
                        },
                      ),
                      SizedBox(height: 14),
                      DashboardTopMetrics(snapshot: _dashboard.snapshot),
                      SizedBox(height: 14),
                      _BlockStatusBanner(guardrails: _guardrails),
                      SizedBox(height: 14),
                      _RiskCoachBanner(snapshot: _dashboard.snapshot),
                      SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 9,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                EquityChart(points: _dashboard.chartPoints),
                                SizedBox(height: 14),
                                RecentTradesTable(
                                  trades: _dashboard.recentTrades,
                                  onAllTradesPressed: _openAllTrades,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DisciplinePanel(
                                  snapshot: _dashboard.snapshot,
                                  guardrails: _guardrails,
                                ),
                                SizedBox(height: 14),
                                RuleBreakPanel(
                                  snapshot: _dashboard.snapshot,
                                  guardrails: _guardrails,
                                  onGuardrailsChanged: _loadDashboard,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openAllTrades() {
    Navigator.push(context, FluentPageRoute(builder: (_) => AllTradesPage()));
  }
}

class _DashboardHeader extends StatelessWidget {
  final bool isLoading;
  final bool isRefreshing;
  final DashboardLiveState? liveState;
  final String? errorMessage;
  final VoidCallback onRefresh;
  final DashboardPeriod selectedPeriod;
  final ValueChanged<DashboardPeriod> onPeriodChanged;

  const _DashboardHeader({
    required this.isLoading,
    required this.isRefreshing,
    required this.liveState,
    required this.errorMessage,
    required this.onRefresh,
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          strings.text('Dashboard'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Text(
            _subtitle(strings),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: errorMessage == null
                  ? AppColors.textSecondary
                  : AppColors.warning,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        _DashboardStatusPill(
          isLoading: isLoading,
          isRefreshing: isRefreshing,
          liveState: liveState,
          hasError: errorMessage != null,
        ),
        SizedBox(width: 8),
        IconButton(
          onPressed: isLoading || isRefreshing ? null : onRefresh,
          icon: isLoading || isRefreshing
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: ProgressRing(strokeWidth: 2),
                )
              : Icon(FluentIcons.refresh, size: 14),
        ),
        SizedBox(width: 8),
        _TimeRangeFilter(
          selectedPeriod: selectedPeriod,
          onPeriodChanged: onPeriodChanged,
        ),
      ],
    );
  }

  String _subtitle(dynamic strings) {
    if (isLoading) {
      return strings.text(
        'Loading trading account, positions, and performance analytics...',
      );
    }
    if (isRefreshing) {
      return strings.isVietnamese
          ? 'Dang cap nhat du lieu moi nhat, man hinh hien tai van giu nguyen.'
          : 'Updating latest data while keeping the current view stable.';
    }
    if (errorMessage != null) return errorMessage!;
    if (liveState != null) {
      final closedTradeTime = liveState!.latestTradeClosedAt;
      final updatedAt = liveState!.positionsCapturedAt ?? liveState!.snapshotCapturedAt;
      final blocked = liveState!.blockState.active;
      final label = strings.isVietnamese
          ? 'MT5 live: ${liveState!.openPositionCount} lenh mo, floating ${dashboardMoney(liveState!.floatingPnl)}.'
          : 'MT5 live: ${liveState!.openPositionCount} open positions, floating ${dashboardMoney(liveState!.floatingPnl)}.';
      final suffix = updatedAt == null
          ? ''
          : strings.isVietnamese
          ? ' Cap nhat ${_formatLiveTime(updatedAt)}.'
          : ' Updated ${_formatLiveTime(updatedAt)}.';
      final tradeSuffix = closedTradeTime == null
          ? ''
          : strings.isVietnamese
          ? ' Lenh dong moi nhat ${_formatLiveTime(closedTradeTime)}.'
          : ' Last closed trade ${_formatLiveTime(closedTradeTime)}.';
      final blockSuffix = blocked
          ? (strings.isVietnamese
                ? ' Guardrail dang khoa giao dich.'
                : ' Guardrails are actively blocking trading.')
          : '';
      return '$label$suffix$tradeSuffix$blockSuffix';
    }
    return strings.text(
      'Trading analytics connected - account, risk, and performance are calculated from broker data.',
    );
  }

  String _formatLiveTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _DashboardStatusPill extends StatelessWidget {
  final bool isLoading;
  final bool isRefreshing;
  final DashboardLiveState? liveState;
  final bool hasError;

  const _DashboardStatusPill({
    required this.isLoading,
    required this.isRefreshing,
    required this.liveState,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLoading || isRefreshing
        ? AppColors.warning
        : hasError
        ? AppColors.danger
        : !(liveState?.protection.backendBlockerRunning ?? true)
        ? AppColors.warning
        : AppColors.success;
    final label = isLoading
        ? 'Loading'
        : isRefreshing
        ? 'Updating'
        : hasError
        ? 'Offline'
        : !(liveState?.protection.backendBlockerRunning ?? true)
        ? 'Starting'
        : 'Live';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRangeFilter extends StatelessWidget {
  final DashboardPeriod selectedPeriod;
  final ValueChanged<DashboardPeriod> onPeriodChanged;

  const _TimeRangeFilter({
    required this.selectedPeriod,
    required this.onPeriodChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final period in DashboardPeriod.values) ...[
          _RangeButton(
            period.label,
            selected: selectedPeriod == period,
            onPressed: () => onPeriodChanged(period),
          ),
          if (period != DashboardPeriod.values.last) SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _RangeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  const _RangeButton(
    this.label, {
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _RiskCoachBanner extends StatelessWidget {
  final DashboardMt5Snapshot snapshot;

  const _RiskCoachBanner({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 38,
      padding: EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.error_badge, size: 15, color: AppColors.danger),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              snapshot.riskMessage,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockStatusBanner extends StatelessWidget {
  final DashboardGuardrailStatus? guardrails;

  const _BlockStatusBanner({required this.guardrails});

  @override
  Widget build(BuildContext context) {
    final block = guardrails?.blockState;
    if (block == null || !block.active) return const SizedBox.shrink();

    final isFullDay = block.fullDayBlock;
    final remaining = block.remainingSeconds;
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    final countdown = isFullDay
        ? 'Until next trading day'
        : '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    final triggerInfo = block.triggeredBy.isNotEmpty
        ? block.triggeredBy.join(', ')
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
            isFullDay ? FluentIcons.blocked_site : FluentIcons.timer,
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
