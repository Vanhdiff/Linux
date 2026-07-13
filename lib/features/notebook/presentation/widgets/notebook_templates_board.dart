import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/catalog/notebook_template_catalog.dart';

class NotebookTemplatesBoard extends StatefulWidget {
  final List<String> categories;
  final List<NotebookTemplate> templates;
  final String? selectedTemplateTitle;
  final ValueChanged<NotebookTemplate> onTemplateSelected;
  final ValueChanged<String> onCategoryCreated;
  final void Function(String currentName, String nextName) onCategoryRenamed;
  final ValueChanged<String> onCategoryDeleted;

  const NotebookTemplatesBoard({
    super.key,
    required this.categories,
    required this.templates,
    required this.selectedTemplateTitle,
    required this.onTemplateSelected,
    required this.onCategoryCreated,
    required this.onCategoryRenamed,
    required this.onCategoryDeleted,
  });

  @override
  State<NotebookTemplatesBoard> createState() => _NotebookTemplatesBoardState();
}

class _NotebookTemplatesBoardState extends State<NotebookTemplatesBoard> {
  bool _showPinned = true;
  final Set<String> _collapsedCategories = {};
  final Map<String, bool> _categoryGridView = {};

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final groupedTemplates = <String, List<NotebookTemplate>>{};
    for (final template in widget.templates) {
      groupedTemplates.putIfAbsent(template.category, () => []).add(template);
    }

    final pinnedTemplates = widget.templates
        .where((t) => t.title == 'Pre-Market Thesis')
        .toList();

    return Container(
      constraints: const BoxConstraints(minHeight: 820),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.text('Templates'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.text(
                        'Your structured frameworks for better trading decisions.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Button(
                onPressed: () => _showCreateCategoryDialog(context),
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(AppColors.primary),
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.add, size: 12, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      strings.text('New folder'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _FolderSectionHeader(
            title: strings.text('Pinned Templates'),
            count: pinnedTemplates.length,
            expanded: _showPinned,
            onToggle: () => setState(() => _showPinned = !_showPinned),
            icon: FluentIcons.pinned,
          ),
          if (_showPinned) ...[
            const SizedBox(height: 14),
            if (pinnedTemplates.isEmpty)
              _EmptyFolder(message: strings.text('No pinned templates'))
            else
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: pinnedTemplates
                    .map(
                      (template) => _TemplateCard(
                        template: template,
                        selected:
                            template.title == widget.selectedTemplateTitle,
                        onTap: () => widget.onTemplateSelected(template),
                        updatedText: _updatedLabel(template.title),
                      ),
                    )
                    .toList(),
              ),
          ],
          const SizedBox(height: 24),

          ...widget.categories.map((category) {
            final templates = groupedTemplates[category] ?? const [];
            final expanded = !_collapsedCategories.contains(category);
            final isGridView = _categoryGridView[category] ?? true;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FolderSectionHeader(
                    title: category,
                    count: templates.length,
                    expanded: expanded,
                    onToggle: () {
                      setState(() {
                        if (_collapsedCategories.contains(category)) {
                          _collapsedCategories.remove(category);
                        } else {
                          _collapsedCategories.add(category);
                        }
                      });
                    },
                    icon: category == 'Mindset'
                        ? FluentIcons.heart
                        : FluentIcons.folder_open,
                    showLayoutSwitcher: expanded && templates.isNotEmpty,
                    isGridView: isGridView,
                    onLayoutChanged: (grid) {
                      setState(() {
                        _categoryGridView[category] = grid;
                      });
                    },
                    onRename: (nextName) =>
                        widget.onCategoryRenamed(category, nextName),
                    onDelete: () => _confirmDeleteCategory(
                      context,
                      category,
                      templates.length,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 14),
                    if (templates.isEmpty)
                      _EmptyFolder(message: strings.text('No templates yet'))
                    else if (isGridView)
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: templates
                            .map(
                              (template) => _TemplateCard(
                                template: template,
                                selected:
                                    template.title ==
                                    widget.selectedTemplateTitle,
                                onTap: () =>
                                    widget.onTemplateSelected(template),
                                updatedText: _updatedLabel(template.title),
                              ),
                            )
                            .toList(),
                      )
                    else
                      Column(
                        children: templates
                            .map(
                              (template) => _TemplateListRow(
                                template: template,
                                selected:
                                    template.title ==
                                    widget.selectedTemplateTitle,
                                onTap: () =>
                                    widget.onTemplateSelected(template),
                                updatedText: _updatedLabel(template.title),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 32),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primarySoft.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  FluentIcons.auto_enhance_on,
                  size: 13,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  strings.text('Consistent systems create consistent results.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCategoryDialog(BuildContext context) async {
    final strings = AppLocalization.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 340),
        title: Text(
          strings.text('Create folder'),
          style: const TextStyle(fontSize: 20),
        ),
        content: SizedBox(
          width: 300,
          height: 38,
          child: TextBox(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            placeholder: strings.text('Folder name'),
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
        ),
        actions: [
          Button(
            child: Text(strings.text('Cancel')),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: Text(strings.text('Create')),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    widget.onCategoryCreated(name);
  }

  Future<void> _confirmDeleteCategory(
    BuildContext context,
    String category,
    int templateCount,
  ) async {
    final strings = AppLocalization.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(strings.text('Delete folder')),
        content: Text(
          templateCount == 0
              ? 'Delete "$category"?'
              : 'Delete "$category" and its $templateCount template(s)?',
        ),
        actions: [
          Button(
            child: Text(strings.text('Cancel')),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: Text(strings.text('Delete')),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onCategoryDeleted(category);
    }
  }
}

class _FolderSectionHeader extends StatefulWidget {
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final IconData icon;
  final bool showLayoutSwitcher;
  final bool isGridView;
  final ValueChanged<bool>? onLayoutChanged;
  final ValueChanged<String>? onRename;
  final VoidCallback? onDelete;

  const _FolderSectionHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.icon,
    this.showLayoutSwitcher = false,
    this.isGridView = true,
    this.onLayoutChanged,
    this.onRename,
    this.onDelete,
  });

  @override
  State<_FolderSectionHeader> createState() => _FolderSectionHeaderState();
}

class _FolderSectionHeaderState extends State<_FolderSectionHeader> {
  final _flyoutController = FlyoutController();

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final strings = AppLocalization.of(context);
    final controller = TextEditingController(text: widget.title);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 340),
        title: Text(
          strings.text('Rename folder'),
          style: const TextStyle(fontSize: 20),
        ),
        content: SizedBox(
          width: 300,
          height: 38,
          child: TextBox(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            placeholder: strings.text('Folder name'),
            onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
          ),
        ),
        actions: [
          Button(
            child: Text(strings.text('Cancel')),
            onPressed: () => Navigator.pop(context),
          ),
          FilledButton(
            child: Text(strings.text('Save')),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
          ),
        ],
      ),
    );
    controller.dispose();
    if (nextName == null) return;
    widget.onRename?.call(nextName);
  }

  void _showContextMenu(Offset position) {
    final strings = AppLocalization.of(context);
    _flyoutController.showFlyout<void>(
      position: position,
      builder: (context) => MenuFlyout(
        items: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.edit_note, size: 14),
            text: Text(strings.text('Rename folder')),
            onPressed: () => _showRenameDialog(context),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.delete, size: 14),
            text: Text(strings.text('Delete folder')),
            onPressed: () => widget.onDelete?.call(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyoutController,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onToggle,
        onSecondaryTapDown: (details) {
          if (widget.onRename != null && widget.onDelete != null) {
            _showContextMenu(details.globalPosition);
          }
        },
        child: Row(
          children: [
            Icon(widget.icon, size: 15, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.shellBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const Spacer(),
            if (widget.showLayoutSwitcher) ...[
              GestureDetector(
                onTap: () => widget.onLayoutChanged?.call(true),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: widget.isGridView
                        ? AppColors.primarySoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    FluentIcons.tiles,
                    size: 13,
                    color: widget.isGridView
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => widget.onLayoutChanged?.call(false),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: !widget.isGridView
                        ? AppColors.primarySoft
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    FluentIcons.list,
                    size: 13,
                    color: !widget.isGridView
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Icon(
              widget.expanded
                  ? FluentIcons.chevron_down_small
                  : FluentIcons.chevron_right_small,
              size: 12,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  final String message;
  const _EmptyFolder({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.shellBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final NotebookTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final String updatedText;

  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
    required this.updatedText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        height: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: template.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(template.icon, size: 13, color: template.accent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  FluentIcons.more,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSkeletonLine(template.accent, 0.75),
                  const SizedBox(height: 6),
                  _buildSkeletonLine(template.accent, 0.9),
                  const SizedBox(height: 6),
                  _buildSkeletonLine(template.accent, 0.55),
                ],
              ),
            ),
            Text(
              updatedText,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLine(Color accentColor, double widthFactor) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: widthFactor,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _updatedLabel(String title) {
  return switch (title) {
    'Pre-Market Thesis' => 'Updated 2 days ago',
    'Trade Review' => 'Updated 1 day ago',
    'Entry Model' => 'Updated 5 hours ago',
    'Emotional Mapping Journal' => 'Updated 3 days ago',
    'Pre-Market Mental Prep' => 'Updated 4 days ago',
    _ => 'Updated recently',
  };
}

class _TemplateListRow extends StatelessWidget {
  final NotebookTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final String updatedText;

  const _TemplateListRow({
    required this.template,
    required this.selected,
    required this.onTap,
    required this.updatedText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: template.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(template.icon, size: 11, color: template.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                template.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              updatedText,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Icon(FluentIcons.more, size: 12, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
