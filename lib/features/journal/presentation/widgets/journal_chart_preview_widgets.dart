import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'journal_chart_import_service.dart';
import 'journal_charts_panel.dart';

class JournalEmptyChartState extends StatelessWidget {
  const JournalEmptyChartState({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.photo2, color: AppColors.primary, size: 18),
          const SizedBox(height: 6),
          Text(
            'No chart attached',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class JournalChartRefTile extends StatelessWidget {
  final JournalChartRef ref;
  final VoidCallback onDelete;

  const JournalChartRefTile({
    super.key,
    required this.ref,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (journalChartCanPreviewImage(ref.path)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 88,
                width: double.infinity,
                child: JournalImagePreview(ref.path),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.photo2, size: 14, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (ref.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ref.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(FluentIcons.delete, size: 13),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class JournalImagePreview extends StatelessWidget {
  final String path;

  const JournalImagePreview(this.path, {super.key});

  @override
  Widget build(BuildContext context) {
    if (journalChartIsWebImage(path)) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const JournalBrokenImagePreview(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const JournalBrokenImagePreview(),
    );
  }
}

class JournalBrokenImagePreview extends StatelessWidget {
  const JournalBrokenImagePreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(FluentIcons.photo_error, color: AppColors.textSecondary),
    );
  }
}
