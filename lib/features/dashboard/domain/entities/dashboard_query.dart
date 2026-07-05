import 'chart_metric_mode.dart';
import 'chart_range.dart';

class DashboardQuery {
  final ChartRange range;
  final ChartMetricMode mode;

  const DashboardQuery({required this.range, required this.mode});

  factory DashboardQuery.initial() {
    return const DashboardQuery(
      range: ChartRange.d30,
      mode: ChartMetricMode.currency,
    );
  }

  DashboardQuery copyWith({ChartRange? range, ChartMetricMode? mode}) {
    return DashboardQuery(range: range ?? this.range, mode: mode ?? this.mode);
  }
}
