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
  DashboardApiView _dashboard = DashboardApiView.empty();
  DashboardGuardrailStatus? _guardrails;
  DashboardPeriod _period = DashboardPeriod.day;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _dataSource = DashboardRemoteDataSource();
    _loadDashboard();
    _refreshTimer = Timer.periodic(Duration(seconds: 15), (_) {
      if (mounted && !_isLoading) {
        _loadDashboard();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _dataSource.close();
    super.dispose();
  }

  Future<void> _loadDashboard({DashboardPeriod? period}) async {
    final nextPeriod = period ?? _period;
    setState(() {
      _period = nextPeriod;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dashboard = await _dataSource.getDashboard(period: nextPeriod);
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
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Backend unavailable: $error';
      });
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
                        errorMessage: _errorMessage,
                        onRefresh: _loadDashboard,
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
  final String? errorMessage;
  final VoidCallback onRefresh;
  final DashboardPeriod selectedPeriod;
  final ValueChanged<DashboardPeriod> onPeriodChanged;

  const _DashboardHeader({
    required this.isLoading,
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
          hasError: errorMessage != null,
        ),
        SizedBox(width: 8),
        IconButton(
          onPressed: isLoading ? null : onRefresh,
          icon: isLoading
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
    if (errorMessage != null) return errorMessage!;
    return strings.text(
      'Trading analytics connected - account, risk, and performance are calculated from broker data.',
    );
  }
}

class _DashboardStatusPill extends StatelessWidget {
  final bool isLoading;
  final bool hasError;

  const _DashboardStatusPill({required this.isLoading, required this.hasError});

  @override
  Widget build(BuildContext context) {
    final color = isLoading
        ? AppColors.warning
        : hasError
        ? AppColors.danger
        : AppColors.success;
    final label = isLoading
        ? 'Syncing'
        : hasError
        ? 'Offline'
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
        color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.20),
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
                  isFullDay ? 'Trading blocked for the day' : 'Trading blocked temporarily',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isFullDay ? AppColors.danger : AppColors.warning,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '$triggerInfo — $countdown',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: (isFullDay ? AppColors.danger : AppColors.warning).withValues(alpha: 0.8),
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
