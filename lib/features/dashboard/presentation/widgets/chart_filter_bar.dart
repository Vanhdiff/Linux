import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/chart_metric_mode.dart';

class ChartFilterBar extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final ChartMetricMode selectedMode;
  final ValueChanged<DateTime> onStartDateChanged;
  final ValueChanged<DateTime> onEndDateChanged;
  final ValueChanged<ChartMetricMode> onModeChanged;
  final bool showDateRange;

  const ChartFilterBar({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.selectedMode,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onModeChanged,
    this.showDateRange = true,
  });

  @override
  State<ChartFilterBar> createState() => _ChartFilterBarState();
}

class _ChartFilterBarState extends State<ChartFilterBar> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(
      text: _formatInput(widget.startDate),
    );
    _endController = TextEditingController(text: _formatInput(widget.endDate));
  }

  @override
  void didUpdateWidget(covariant ChartFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_startController, widget.startDate);
    _syncController(_endController, widget.endDate);
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.showDateRange) ...[
          _DateInput(
            label: 'From',
            controller: _startController,
            onDateChanged: widget.onStartDateChanged,
          ),
          SizedBox(width: 6),
          _DateInput(
            label: 'To',
            controller: _endController,
            onDateChanged: widget.onEndDateChanged,
          ),
          SizedBox(width: 8),
        ],
        _MiniChip(
          label: r'$',
          selected: widget.selectedMode == ChartMetricMode.currency,
          onTap: () => widget.onModeChanged(ChartMetricMode.currency),
        ),
        SizedBox(width: 4),
        _MiniChip(
          label: 'R',
          selected: widget.selectedMode == ChartMetricMode.rMultiple,
          onTap: () => widget.onModeChanged(ChartMetricMode.rMultiple),
        ),
        SizedBox(width: 4),
        _MiniChip(
          label: '%',
          selected: widget.selectedMode == ChartMetricMode.percent,
          onTap: () => widget.onModeChanged(ChartMetricMode.percent),
        ),
      ],
    );
  }

  void _syncController(TextEditingController controller, DateTime value) {
    final formatted = _formatInput(value);
    if (controller.text == formatted) return;
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _DateInput extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<DateTime> onDateChanged;

  const _DateInput({
    required this.label,
    required this.controller,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(width: 4),
        SizedBox(
          width: 86,
          height: 24,
          child: TextBox(
            controller: controller,
            placeholder: 'yyyy-mm-dd',
            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            inputFormatters: [LengthLimitingTextInputFormatter(10)],
            onChanged: (value) {
              final parsed = _parseInput(value);
              if (parsed != null) onDateChanged(parsed);
            },
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

DateTime? _parseInput(String value) {
  if (value.length != 10) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _formatInput(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
