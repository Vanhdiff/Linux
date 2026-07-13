import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import 'journal_chart_tool_card.dart';

class JournalChartRef {
  final String timeframe;
  final String path;
  final String note;

  const JournalChartRef({
    required this.timeframe,
    required this.path,
    this.note = '',
  });

  factory JournalChartRef.fromJson(Map<String, dynamic> json) {
    return JournalChartRef(
      timeframe: json['timeframe'] as String? ?? 'MTF',
      path: json['path'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }
}

class JournalChartsPanel extends StatelessWidget {
  final List<JournalChartRef> refs;
  final ValueChanged<List<JournalChartRef>> onRefsChanged;

  const JournalChartsPanel({
    super.key,
    required this.refs,
    required this.onRefsChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Charts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${refs.length} saved',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            'Paste an image from clipboard or choose a screenshot from folder.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final timeframe in const ['MTF', 'HTF', 'LTF']) ...[
                Expanded(
                  child: JournalChartToolCard(
                    timeframe: timeframe,
                    refs: refs
                        .where((ref) => ref.timeframe == timeframe)
                        .toList(growable: false),
                    onAdd: (ref) => onRefsChanged([...refs, ref]),
                    onDelete: (ref) {
                      final next = List<JournalChartRef>.from(refs);
                      next.remove(ref);
                      onRefsChanged(next);
                    },
                  ),
                ),
                if (timeframe != 'LTF') SizedBox(width: 14),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
