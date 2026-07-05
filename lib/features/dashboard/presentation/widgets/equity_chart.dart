import 'package:fluent_ui/fluent_ui.dart';
import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/chart_metric_mode.dart';
import '../models/dashboard_mt5_snapshot.dart';
import 'chart_filter_bar.dart';

class EquityChart extends StatefulWidget {
  final List<DashboardChartPoint> points;

  const EquityChart({super.key, this.points = const []});

  @override
  State<EquityChart> createState() => _EquityChartState();
}

class _EquityChartState extends State<EquityChart> {
  ChartMetricMode _mode = ChartMetricMode.currency;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final availableRange = _availableRange(widget.points);
    final startDate = _startDate ?? availableRange.start;
    final endDate = _endDate ?? availableRange.end;
    final filteredPoints = _filterPoints(widget.points, startDate, endDate);

    return Container(
      height: 228,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                strings.text('Account Balance'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Spacer(),
              ChartFilterBar(
                startDate: startDate,
                endDate: endDate,
                selectedMode: _mode,
                onStartDateChanged: (date) {
                  setState(() {
                    _startDate = date;
                    if (date.isAfter(endDate)) {
                      _endDate = date;
                    }
                  });
                },
                onEndDateChanged: (date) {
                  setState(() {
                    _endDate = date;
                    if (date.isBefore(startDate)) {
                      _startDate = date;
                    }
                  });
                },
                onModeChanged: (mode) {
                  setState(() {
                    _mode = mode;
                  });
                },
                showDateRange: false,
              ),
            ],
          ),
          SizedBox(height: 10),
          Expanded(
            child: CustomPaint(
              painter: _CompactChartPainter(
                mode: _mode,
                points: filteredPoints,
              ),
              child: Container(),
            ),
          ),
        ],
      ),
    );
  }
}

List<DashboardChartPoint> _filterPoints(
  List<DashboardChartPoint> points,
  DateTime startDate,
  DateTime endDate,
) {
  final filtered = points.where((point) {
    if (point.closedAt == null) return true;
    final closedDate = _dateOnly(point.closedAt!);
    return !closedDate.isBefore(startDate) && !closedDate.isAfter(endDate);
  }).toList();
  return filtered;
}

_DateRange _availableRange(List<DashboardChartPoint> points) {
  final dates = points
      .map((point) => point.closedAt)
      .whereType<DateTime>()
      .map(_dateOnly)
      .toList();
  if (dates.isEmpty) {
    final today = _dateOnly(DateTime.now());
    return _DateRange(start: today.subtract(Duration(days: 30)), end: today);
  }
  dates.sort();
  return _DateRange(start: dates.first, end: dates.last);
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

class _CompactChartPainter extends CustomPainter {
  final ChartMetricMode mode;
  final List<DashboardChartPoint> points;

  _CompactChartPainter({required this.mode, required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 36.0;
    final bottomPad = 18.0;
    final chartWidth = size.width - leftPad;
    final chartHeight = size.height - bottomPad;

    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    final axisPaint = Paint()
      ..color = Color(0xFFE6E0F0)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: Color(0xFFB0A8BE),
      fontSize: 8,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < 4; i++) {
      final y = chartHeight * i / 3;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
    }

    canvas.drawLine(
      Offset(leftPad, 0),
      Offset(leftPad, chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(leftPad, chartHeight),
      Offset(size.width, chartHeight),
      axisPaint,
    );

    final values = points.map(_valueForMode).toList();
    final bounds = _bounds(values);
    final yLabels = _buildYLabels(bounds.min, bounds.max);
    for (int i = 0; i < yLabels.length; i++) {
      final y = chartHeight * i / 3;
      final tp = TextPainter(
        text: TextSpan(text: yLabels[i], style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 5));
    }

    final xLabels = _buildXLabels(points);
    for (final label in xLabels) {
      final x = leftPad + chartWidth * label.position;
      final tp = TextPainter(
        text: TextSpan(text: label.text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartHeight + 4));
    }

    if (points.length < 2) {
      _drawEmptyState(canvas, size, leftPad, chartHeight);
      return;
    }

    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = leftPad + chartWidth * i / (points.length - 1);
      final value = _valueForMode(points[i]);
      final normalized = (value - bounds.min) / (bounds.max - bounds.min);
      final y = chartHeight - chartHeight * normalized;
      offsets.add(Offset(x, y));
    }

    final path = _smoothPath(offsets);

    final fillPath = Path.from(path)
      ..lineTo(leftPad + chartWidth, chartHeight)
      ..lineTo(leftPad, chartHeight)
      ..close();

    final isDown = offsets.last.dy > offsets.first.dy;
    final accent = isDown ? AppColors.danger : AppColors.success;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accent.withValues(alpha: 0.18),
          accent.withValues(alpha: 0.06),
          const Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromLTWH(leftPad, 0, chartWidth, chartHeight));

    canvas.drawPath(fillPath, fillPaint);

    final glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawPath(path, glowPaint);

    final linePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, linePaint);
  }

  Path _smoothPath(List<Offset> offsets) {
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 0; i < offsets.length - 1; i++) {
      final current = offsets[i];
      final next = offsets[i + 1];
      final controlX = current.dx + (next.dx - current.dx) / 2;
      path.cubicTo(controlX, current.dy, controlX, next.dy, next.dx, next.dy);
    }
    return path;
  }

  double _valueForMode(DashboardChartPoint point) {
    switch (mode) {
      case ChartMetricMode.currency:
        return point.balance;
      case ChartMetricMode.rMultiple:
        return point.cumulativeR;
      case ChartMetricMode.percent:
        return point.percentReturn;
    }
  }

  _ChartBounds _bounds(List<double> values) {
    if (values.isEmpty) return const _ChartBounds(min: 0, max: 1);
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    if (min == max) {
      final padding = min.abs() * 0.05 + 1;
      min -= padding;
      max += padding;
    } else {
      final padding = (max - min) * 0.12;
      min -= padding;
      max += padding;
    }
    return _ChartBounds(min: min, max: max);
  }

  List<String> _buildYLabels(double min, double max) {
    return List.generate(4, (index) {
      final value = max - (max - min) * index / 3;
      switch (mode) {
        case ChartMetricMode.currency:
          return _compactMoney(value);
        case ChartMetricMode.rMultiple:
          return '${value.toStringAsFixed(1)}R';
        case ChartMetricMode.percent:
          return '${value.toStringAsFixed(1)}%';
      }
    });
  }

  List<_AxisLabel> _buildXLabels(List<DashboardChartPoint> points) {
    if (points.isEmpty) return const [];
    final indexes = points.length <= 3
        ? List.generate(points.length, (index) => index)
        : <int>[0, (points.length / 2).floor(), points.length - 1];
    return indexes.map((index) {
      return _AxisLabel(
        position: points.length == 1 ? 0 : index / (points.length - 1),
        text: _formatDate(points[index].closedAt),
      );
    }).toList();
  }

  void _drawEmptyState(
    Canvas canvas,
    Size size,
    double leftPad,
    double chartHeight,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: 'No closed trades yet',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(leftPad + (size.width - leftPad - tp.width) / 2, chartHeight / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CompactChartPainter oldDelegate) {
    return oldDelegate.mode != mode || oldDelegate.points != points;
  }
}

class _ChartBounds {
  final double min;
  final double max;

  const _ChartBounds({required this.min, required this.max});
}

class _AxisLabel {
  final double position;
  final String text;

  const _AxisLabel({required this.position, required this.text});
}

class _DateRange {
  final DateTime start;
  final DateTime end;

  const _DateRange({required this.start, required this.end});
}

String _compactMoney(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  if (absolute >= 1000) {
    return '$sign\$${(absolute / 1000).toStringAsFixed(1)}K';
  }
  return '$sign\$${absolute.toStringAsFixed(0)}';
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month';
}
