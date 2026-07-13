import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';

class NotebookNote {
  final int? id;
  final String title;
  final String preview;
  final String date;
  final IconData icon;
  final Color color;
  final bool pinned;

  const NotebookNote({
    this.id,
    required this.title,
    required this.preview,
    required this.date,
    required this.icon,
    required this.color,
    this.pinned = false,
  });
}

class NotebookTemplate {
  final String title;
  String category;
  final int count;
  final Color accent;
  final IconData icon;

  NotebookTemplate({
    required this.title,
    required this.category,
    required this.count,
    Color? accent,
    this.icon = FluentIcons.edit_note,
  }) : accent = accent ?? AppColors.primary;
}

abstract final class NotebookTemplateCatalog {
  static List<NotebookTemplate> get templates => [
    NotebookTemplate(
      title: 'Pre-Market Thesis',
      category: 'My Templates',
      count: 1,
      accent: AppColors.warning,
      icon: FluentIcons.lightbulb,
    ),
    NotebookTemplate(
      title: 'Trade Review',
      category: 'Playbook',
      count: 2,
      accent: AppColors.warning,
      icon: FluentIcons.task_manager,
    ),
    NotebookTemplate(
      title: 'Entry Model',
      category: 'Playbook',
      count: 2,
      accent: AppColors.danger,
      icon: FluentIcons.edit_note,
    ),
    NotebookTemplate(
      title: 'Emotional Mapping Journal',
      category: 'Mindset',
      count: 4,
      accent: AppColors.success,
      icon: FluentIcons.heart,
    ),
    NotebookTemplate(
      title: 'Pre-Market Mental Prep',
      category: 'Mindset',
      count: 4,
      accent: AppColors.danger,
      icon: FluentIcons.heart_fill,
    ),
  ];
}
