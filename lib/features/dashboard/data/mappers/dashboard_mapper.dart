import '../../domain/entities/chart_metric_mode.dart';
import '../../domain/entities/chart_range.dart';
import '../../domain/entities/dashboard_query.dart';

class DashboardQueryMapper {
  static String rangeToApi(ChartRange range) {
    switch (range) {
      case ChartRange.d7:
        return '7d';
      case ChartRange.d30:
        return '30d';
      case ChartRange.d90:
        return '90d';
      case ChartRange.d180:
        return '180d';
      case ChartRange.y1:
        return '1y';
      case ChartRange.all:
        return 'all';
    }
  }

  static String modeToApi(ChartMetricMode mode) {
    switch (mode) {
      case ChartMetricMode.currency:
        return 'currency';
      case ChartMetricMode.rMultiple:
        return 'r';
      case ChartMetricMode.percent:
        return 'percent';
    }
  }

  static Map<String, dynamic> toQueryParams(DashboardQuery query) {
    return {'range': rangeToApi(query.range), 'mode': modeToApi(query.mode)};
  }
}
