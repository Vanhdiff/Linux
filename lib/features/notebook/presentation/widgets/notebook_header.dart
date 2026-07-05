import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';

class NotebookHeader extends StatelessWidget {
  final VoidCallback onCreateBlankNote;
  final VoidCallback onCreateFromTemplate;

  const NotebookHeader({
    super.key,
    required this.onCreateBlankNote,
    required this.onCreateFromTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          strings.text('Notebook'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            strings.text('Think before you trade. Review before you repeat.'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DropDownButton(
          style: ButtonStyle(
            backgroundColor: WidgetStatePropertyAll(AppColors.primary),
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            padding: WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.add, size: 14),
              SizedBox(width: 6),
              Text(
                strings.text('New Note'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              SizedBox(width: 4),
              Icon(FluentIcons.chevron_down_small, size: 12),
            ],
          ),
          items: [
            MenuFlyoutItem(
              leading: Icon(FluentIcons.save_template, size: 14),
              text: Text(strings.text('Create from Template')),
              onPressed: onCreateFromTemplate,
            ),
            MenuFlyoutItem(
              leading: Icon(FluentIcons.page_add, size: 14),
              text: Text(strings.text('Create Blank Note')),
              onPressed: onCreateBlankNote,
            ),
          ],
        ),
      ],
    );
  }
}
