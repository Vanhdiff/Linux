import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'journal_shared_widgets.dart';

class JournalHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  const JournalHeader({super.key, required this.title, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Button(
          onPressed: onBack ?? () {},
          style: ButtonStyle(
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.chevron_left, size: 12),
              SizedBox(width: 5),
              Text('Back', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              SizedBox(width: 10),
              JournalPill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.lightning_bolt,
                      size: 12,
                      color: AppColors.warning,
                    ),
                    SizedBox(width: 4),
                    Text('Auto-imported'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Text(
          'Review context, screenshots, and lessons',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
