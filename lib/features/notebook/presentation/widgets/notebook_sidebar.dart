import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';
import '../data/notebook_sample_data.dart';

class NotebookSidebar extends StatefulWidget {
  final List<NotebookNote> pinnedNotes;
  final List<NotebookNote> recentNotes;
  final String? selectedNoteTitle;
  final ValueChanged<NotebookNote> onNoteSelected;
  final ValueChanged<NotebookNote> onTogglePinned;
  final void Function(NotebookNote note, String title) onRenameNote;
  final ValueChanged<NotebookNote> onDeleteNote;
  final VoidCallback? onCreateNote;

  const NotebookSidebar({
    super.key,
    required this.pinnedNotes,
    required this.recentNotes,
    required this.selectedNoteTitle,
    required this.onNoteSelected,
    required this.onTogglePinned,
    required this.onRenameNote,
    required this.onDeleteNote,
    this.onCreateNote,
  });

  @override
  State<NotebookSidebar> createState() => _NotebookSidebarState();
}

class _NotebookSidebarState extends State<NotebookSidebar> {
  final _searchController = TextEditingController();
  bool _showPinned = true;
  bool _showRecent = true;
  bool _showAllNotes = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final pinnedNotes = widget.pinnedNotes
        .where(_matchesSearch)
        .toList(growable: false);
    final allNotes = widget.recentNotes
        .where(_matchesSearch)
        .toList(growable: false);
    final recentNotes = allNotes.take(2).toList(growable: false);

    return Container(
      width: 290,
      constraints: const BoxConstraints(minHeight: 820),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SearchBox(
            controller: _searchController,
            hasQuery: _searchController.text.trim().isNotEmpty,
            onChanged: (_) => setState(() {}),
            onClear: () {
              _searchController.clear();
              setState(() {});
            },
            onCreateNote: widget.onCreateNote,
          ),
          const SizedBox(height: 24),
          _SectionHeader(
            '${strings.text('Pinned notes').toUpperCase()}  ${pinnedNotes.length}',
            expanded: _showPinned,
            onToggle: () => setState(() => _showPinned = !_showPinned),
          ),
          if (_showPinned) ...[
            const SizedBox(height: 8),
            if (pinnedNotes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4, bottom: 8),
                child: Text(
                  strings.text('No pinned notes'),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              )
            else
              ...pinnedNotes.map(
                (note) => _NoteTile(
                  note,
                  selected: note.title == widget.selectedNoteTitle,
                  onTap: () => widget.onNoteSelected(note),
                  onTogglePinned: () => widget.onTogglePinned(note),
                  onRename: (title) => widget.onRenameNote(note, title),
                  onDelete: () => widget.onDeleteNote(note),
                ),
              ),
          ],
          const SizedBox(height: 20),
          _SectionHeader(
            strings.text('Recent notes').toUpperCase(),
            expanded: _showRecent,
            onToggle: () => setState(() => _showRecent = !_showRecent),
          ),
          if (_showRecent) ...[
            const SizedBox(height: 8),
            if (recentNotes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 4, bottom: 8),
                child: Text(
                  strings.text('No recent notes'),
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              )
            else
              ...recentNotes.map(
                (note) => _NoteTile(
                  note,
                  selected: note.title == widget.selectedNoteTitle,
                  onTap: () => widget.onNoteSelected(note),
                  onTogglePinned: () => widget.onTogglePinned(note),
                  onRename: (title) => widget.onRenameNote(note, title),
                  onDelete: () => widget.onDeleteNote(note),
                ),
              ),
          ],
          const SizedBox(height: 20),
          _SectionHeader(
            '${strings.text('All notes').toUpperCase()}  ${allNotes.length}',
            expanded: _showAllNotes,
            onToggle: () => setState(() => _showAllNotes = !_showAllNotes),
          ),
          if (_showAllNotes) ...[
            const SizedBox(height: 8),
            if (allNotes.isEmpty)
              _EmptySearchResult(hasQuery: _searchController.text.isNotEmpty)
            else
              ...allNotes.map(
                (note) => _NoteTile(
                  note,
                  compact: true,
                  selected: note.title == widget.selectedNoteTitle,
                  onTap: () => widget.onNoteSelected(note),
                  onTogglePinned: () => widget.onTogglePinned(note),
                  onRename: (title) => widget.onRenameNote(note, title),
                  onDelete: () => widget.onDeleteNote(note),
                ),
              ),
          ],
        ],
      ),
    );
  }

  bool _matchesSearch(NotebookNote note) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return note.title.toLowerCase().contains(query) ||
        note.preview.toLowerCase().contains(query) ||
        note.date.toLowerCase().contains(query);
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final bool hasQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback? onCreateNote;

  const _SearchBox({
    required this.controller,
    required this.hasQuery,
    required this.onChanged,
    required this.onClear,
    this.onCreateNote,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: TextBox(
              controller: controller,
              placeholder: strings.text('Search notes...'),
              onChanged: onChanged,
              maxLines: 1,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              prefix: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
                child: Icon(
                  FluentIcons.search,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              suffix: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: Text(
                  '⌘K',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              placeholderStyle: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              decoration: WidgetStatePropertyAll(
                BoxDecoration(
                  color: AppColors.shellBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hasQuery ? onClear : onCreateNote,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hasQuery ? AppColors.shellBg : AppColors.primary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hasQuery ? AppColors.border : AppColors.primary.withValues(alpha: 0.8),
              ),
            ),
            child: Icon(
              hasQuery ? FluentIcons.clear : FluentIcons.edit_note,
              size: 16,
              color: hasQuery ? AppColors.textSecondary : Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  final bool hasQuery;

  const _EmptySearchResult({required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.shellBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        hasQuery
            ? strings.text('No matching notes')
            : strings.text('No notes yet'),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  const _SectionHeader(
    this.title, {
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Icon(
              expanded
                  ? FluentIcons.chevron_down_small
                  : FluentIcons.chevron_right_small,
              size: 10,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteTile extends StatefulWidget {
  final NotebookNote note;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTogglePinned;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;

  const _NoteTile(
    this.note, {
    this.compact = false,
    required this.selected,
    required this.onTap,
    required this.onTogglePinned,
    required this.onRename,
    required this.onDelete,
  });

  @override
  State<_NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends State<_NoteTile> {
  final _flyoutController = FlyoutController();
  bool _isHovered = false;

  @override
  void dispose() {
    _flyoutController.dispose();
    super.dispose();
  }

  void _showContextMenu(Offset position) {
    final strings = AppLocalization.of(context);
    _flyoutController.showFlyout<void>(
      position: position,
      builder: (context) => MenuFlyout(
        items: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.edit_note, size: 14),
            text: Text(strings.text('Rename note')),
            onPressed: () => _showRenameDialog(this.context),
          ),
          MenuFlyoutItem(
            leading: Icon(
              widget.note.pinned ? FluentIcons.pinned : FluentIcons.pin,
              size: 14,
            ),
            text: Text(
              widget.note.pinned
                  ? strings.text('Unpin note')
                  : strings.text('Pin note'),
            ),
            onPressed: widget.onTogglePinned,
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.delete, size: 14),
            text: Text(strings.text('Delete note')),
            onPressed: () => _confirmDelete(this.context),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    final strings = AppLocalization.of(context);
    final controller = TextEditingController(text: widget.note.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 340),
        title: Text(
          strings.text('Rename note'),
          style: const TextStyle(fontSize: 20),
        ),
        content: SizedBox(
          width: 300,
          height: 38,
          child: TextBox(
            controller: controller,
            autofocus: true,
            maxLines: 1,
            placeholder: strings.text('Note title'),
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
    if (title == null || title.trim().isEmpty) return;
    widget.onRename(title.trim());
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final strings = AppLocalization.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(strings.text('Delete note')),
        content: Text('Delete "${widget.note.title}"?'),
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
      widget.onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: _flyoutController,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          child: Container(
            margin: EdgeInsets.only(bottom: widget.compact ? 6 : 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppColors.primarySoft
                  : (_isHovered ? AppColors.shellBg : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.selected
                    ? AppColors.primary.withValues(alpha: 0.45)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: widget.note.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    widget.note.icon,
                    size: 14,
                    color: widget.note.color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.note.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.note.pinned)
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: Icon(
                                FluentIcons.pin,
                                size: 10,
                                color: AppColors.danger.withValues(alpha: 0.8),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.note.preview,
                        maxLines: widget.compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.note.date,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
