import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/services/api/api_client.dart';
import '../../../../app/state/active_account_session.dart';
import '../../../../app/theme/app_colors.dart';
import '../../data/catalog/notebook_template_catalog.dart';
import '../widgets/notebook_sidebar.dart';
import '../widgets/notebook_templates_board.dart';

class NotebookPage extends StatefulWidget {
  const NotebookPage({super.key});

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage> {
  final ApiClient _apiClient = ApiClient();
  int get _accountId => ActiveAccountSession.accountId;
  late final List<NotebookTemplate> _templates;
  late final List<String> _templateCategories;
  List<_NotebookEntry> _entries = [];
  var _selectedIndex = 0;
  String? _selectedTemplateTitle;

  @override
  void initState() {
    super.initState();
    _templates = NotebookTemplateCatalog.templates;
    _templateCategories = _orderedTemplateCategories(_templates);
    _entries = [_newBlankEntry()];
    _selectedTemplateTitle = _entries.first.template;
    _loadRemoteNotes();
  }

  @override
  void dispose() {
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.shellBg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 24.0;
          final contentWidth = constraints.maxWidth - horizontalPadding * 2;
          final targetWidth = contentWidth * 0.95;
          final pageWidth = targetWidth < 1090 ? 1090.0 : targetWidth;
          final scrollWidth = pageWidth > contentWidth
              ? pageWidth
              : contentWidth;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 20,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scrollWidth,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: pageWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NotebookSidebar(
                          pinnedNotes: _pinnedNotes,
                          recentNotes: _recentNotes,
                          selectedNoteTitle: _current.title,
                          onNoteSelected: _selectNote,
                          onTogglePinned: _togglePinned,
                          onRenameNote: _renameNote,
                          onDeleteNote: _deleteNote,
                          onCreateNote:
                              _createBlankNote, // bind new note action
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: NotebookTemplatesBoard(
                            categories: _templateCategories,
                            templates: _templates,
                            selectedTemplateTitle: _selectedTemplateTitle,
                            onTemplateSelected: _createFromTemplate,
                            onCategoryCreated: _createTemplateCategory,
                            onCategoryRenamed: _renameTemplateCategory,
                            onCategoryDeleted: _deleteTemplateCategory,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  _NotebookEntry get _current => _entries[_selectedIndex];

  List<NotebookNote> get _pinnedNotes => _entries
      .where((entry) => entry.pinned)
      .map((entry) => entry.toNote())
      .toList(growable: false);

  List<NotebookNote> get _recentNotes =>
      _entries.map((entry) => entry.toNote()).toList(growable: false);

  void _selectNote(NotebookNote note) {
    final index = _entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
    if (index == -1) return;
    setState(() {
      _selectedIndex = index;
      _selectedTemplateTitle = _entries[index].template;
    });
    _openEditor(_entries[index]);
  }

  Future<void> _togglePinned(NotebookNote note) async {
    final index = _entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
    if (index == -1) return;
    final entry = _entries[index];
    setState(() {
      entry.pinned = !entry.pinned;
      entry.saved = false;
    });
    await _persistEntry(entry);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _renameNote(NotebookNote note, String title) async {
    final index = _findNoteIndex(note);
    if (index == -1) return;
    setState(() {
      _entries[index].title = title;
      _entries[index].updatedAt = 'saved now';
      _entries[index].saved = false;
      _selectedIndex = index;
    });
    await _persistEntry(_entries[index]);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteNote(NotebookNote note) async {
    final index = _findNoteIndex(note);
    if (index == -1) return;
    final removed = _entries[index];
    final previousIndex = _selectedIndex;
    setState(() {
      _entries.removeAt(index);
      if (_entries.isEmpty) {
        _entries.add(_newBlankEntry());
      }
      _selectedIndex = index >= _entries.length ? _entries.length - 1 : index;
      _selectedTemplateTitle = _entries[_selectedIndex].template;
    });

    if (removed.id == null) return;
    try {
      await _apiClient.delete('/notebook/notes/${removed.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final restoreIndex = index > _entries.length ? _entries.length : index;
        _entries.insert(restoreIndex, removed);
        _selectedIndex = previousIndex >= _entries.length
            ? _entries.length - 1
            : previousIndex;
        _selectedTemplateTitle = _entries[_selectedIndex].template;
      });
    }
  }

  int _findNoteIndex(NotebookNote note) {
    return _entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
  }

  void _createBlankNote() {
    final entry = _newBlankEntry();
    setState(() {
      _entries.insert(0, entry);
      _selectedIndex = 0;
      _selectedTemplateTitle = entry.template;
    });
    _openEditor(entry);
  }

  void _createFromTemplate(NotebookTemplate template) {
    final entry = _entryFromTemplate(template);
    setState(() {
      _entries.insert(0, entry);
      _selectedIndex = 0;
      _selectedTemplateTitle = template.title;
    });
    _openEditor(entry);
  }

  void _renameTemplateCategory(String currentName, String nextName) {
    final cleanName = nextName.trim();
    if (cleanName.isEmpty || cleanName == currentName) return;
    setState(() {
      for (final template in _templates) {
        if (template.category == currentName) {
          template.category = cleanName;
        }
      }
      final currentIndex = _templateCategories.indexOf(currentName);
      final existingIndex = _templateCategories.indexOf(cleanName);
      if (existingIndex != -1 && existingIndex != currentIndex) {
        _templateCategories.removeAt(currentIndex);
      } else if (currentIndex != -1) {
        _templateCategories[currentIndex] = cleanName;
      }
    });
  }

  void _createTemplateCategory(String name) {
    final cleanName = name.trim();
    if (cleanName.isEmpty || _templateCategories.contains(cleanName)) return;
    setState(() {
      _templateCategories.add(cleanName);
    });
  }

  void _deleteTemplateCategory(String name) {
    setState(() {
      _templateCategories.remove(name);
      _templates.removeWhere((template) => template.category == name);
      final selectedStillExists = _templates.any(
        (template) => template.title == _selectedTemplateTitle,
      );
      if (!selectedStillExists) {
        _selectedTemplateTitle = _templates.isEmpty
            ? null
            : _templates.first.title;
      }
    });
  }

  _NotebookEntry _entryFromTemplate(NotebookTemplate template) {
    final plan = switch (template.title) {
      'Trade Review' => 'What happened? What should repeat? What changes next?',
      'Entry Model' =>
        'Context. Trigger. Invalidation. Target. Skip condition.',
      'Emotional Mapping Journal' =>
        'Current emotion. What I am tempted to do. Rule that protects me.',
      'Pre-Market Mental Prep' =>
        'State check. Risk limit. One behavior to protect today.',
      _ =>
        'Market context. Key levels. Bullish plan. Bearish plan. Invalidation.',
    };
    return _NotebookEntry(
      title: template.title,
      template: template.title,
      plan: plan,
      note: '',
      updatedAt: 'now',
      icon: template.icon,
      accent: template.accent,
      iconKey: _iconKeyFromTemplate(template),
      accentKey: _accentKeyFromColor(template.accent),
      saved: false,
      tasks: [
        _NotebookTask('Write the core thesis'),
        _NotebookTask('Define risk before entry'),
        _NotebookTask('Review after session'),
      ],
    );
  }

  Future<void> _openEditor(_NotebookEntry entry) async {
    final index = _entries.indexOf(entry);
    final result = await Navigator.push(
      context,
      FluentPageRoute(
        builder: (_) => _NotebookEditorPage(
          entries: _entries,
          initialIndex: index == -1 ? 0 : index,
          apiClient: _apiClient,
        ),
      ),
    );
    if (result == 'create_note') {
      _createBlankNote();
      return;
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _persistEntry(_NotebookEntry entry) async {
    try {
      final response = entry.id == null
          ? await _apiClient.postJson(
              '/notebook/notes',
              entry.toJson(accountId: _accountId),
            )
          : await _apiClient.patchJson(
              '/notebook/notes/${entry.id}',
              entry.toJson(accountId: _accountId),
            );
      final saved = _NotebookEntry.fromJson(response as Map<String, dynamic>);
      final index = _entries.indexOf(entry);
      if (index != -1) {
        _entries[index] = saved;
        _selectedIndex = index;
      }
    } catch (_) {
      entry.pinned = !entry.pinned;
    }
  }

  Future<void> _loadRemoteNotes() async {
    try {
      final response = await _apiClient.getJson(
        '/notebook/notes',
        queryParameters: {'account_id': '$_accountId'},
      );
      final items = response as List<dynamic>;
      if (!mounted) return;
      if (items.isEmpty) {
        setState(() {
          _entries = [_newBlankEntry()];
          _selectedIndex = 0;
          _selectedTemplateTitle = _entries.first.template;
        });
        return;
      }
      setState(() {
        _entries = items
            .map(
              (item) => _NotebookEntry.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        _selectedIndex = 0;
        _selectedTemplateTitle = _entries.first.template;
      });
    } catch (_) {
      // Keep local starter notes visible while the trading service warms up.
    }
  }
}

class _NotebookEditorPage extends StatefulWidget {
  final List<_NotebookEntry> entries;
  final int initialIndex;
  final ApiClient apiClient;

  const _NotebookEditorPage({
    required this.entries,
    required this.initialIndex,
    required this.apiClient,
  });

  @override
  State<_NotebookEditorPage> createState() => _NotebookEditorPageState();
}

class _NotebookEditorPageState extends State<_NotebookEditorPage> {
  final _titleController = TextEditingController();
  final _planController = TextEditingController();
  final _noteController = TextEditingController();
  final _taskController = TextEditingController();
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _loadEntry(_current);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _planController.dispose();
    _noteController.dispose();
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      color: AppColors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = 24.0;
          final contentWidth = constraints.maxWidth - horizontalPadding * 2;
          final pageWidth = contentWidth < 1090 ? 1090.0 : contentWidth;
          final scrollWidth = pageWidth > contentWidth
              ? pageWidth
              : contentWidth;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              18,
              horizontalPadding,
              24,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: scrollWidth,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: pageWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Button(
                              onPressed: () => Navigator.pop(context),
                              style: ButtonStyle(
                                padding: WidgetStatePropertyAll(
                                  EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
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
                                  Icon(FluentIcons.back, size: 15),
                                  SizedBox(width: 8),
                                  Text(
                                    strings.text('Back to Notebook'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NotebookSidebar(
                              pinnedNotes: _pinnedNotes,
                              recentNotes: _recentNotes,
                              selectedNoteTitle: _current.title,
                              onNoteSelected: _selectNote,
                              onTogglePinned: _togglePinned,
                              onRenameNote: _renameNote,
                              onDeleteNote: _deleteNote,
                              onCreateNote: () =>
                                  Navigator.pop(context, 'create_note'),
                            ),
                            SizedBox(width: 18),
                            Expanded(
                              child: _NotebookEditor(
                                entry: _current,
                                titleController: _titleController,
                                planController: _planController,
                                noteController: _noteController,
                                taskController: _taskController,
                                onSave: _saveCurrent,
                                onChanged: _markDirty,
                                onAddTask: _addTask,
                                onAddTaskPreset: _addTaskPreset,
                                onClearDoneTasks: _clearDoneTasks,
                                onToggleTask: _toggleTask,
                                onDeleteTask: _deleteTask,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  _NotebookEntry get _current => widget.entries[_selectedIndex];

  List<NotebookNote> get _pinnedNotes => widget.entries
      .where((entry) => entry.pinned)
      .map((entry) => entry.toNote())
      .toList(growable: false);

  List<NotebookNote> get _recentNotes =>
      widget.entries.map((entry) => entry.toNote()).toList(growable: false);

  void _loadEntry(_NotebookEntry entry) {
    _titleController.text = entry.title;
    _planController.text = entry.plan;
    _noteController.text = entry.note;
    _taskController.clear();
  }

  Future<void> _selectNote(NotebookNote note) async {
    final index = widget.entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
    if (index == -1) return;
    await _saveCurrent();
    if (!mounted) return;
    setState(() {
      _selectedIndex = index;
      _loadEntry(_current);
    });
  }

  Future<void> _togglePinned(NotebookNote note) async {
    final index = widget.entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
    if (index == -1) return;
    setState(() {
      widget.entries[index].pinned = !widget.entries[index].pinned;
      widget.entries[index].saved = false;
    });
    if (index == _selectedIndex) {
      await _saveCurrent();
    } else {
      await _persistEntry(widget.entries[index]);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _renameNote(NotebookNote note, String title) async {
    final index = _findNoteIndex(note);
    if (index == -1) return;
    await _saveCurrent();
    if (!mounted) return;
    setState(() {
      widget.entries[index].title = title;
      widget.entries[index].updatedAt = 'saved now';
      widget.entries[index].saved = false;
      _selectedIndex = index;
      _loadEntry(_current);
    });
    await _persistEntry(widget.entries[index]);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteNote(NotebookNote note) async {
    final index = _findNoteIndex(note);
    if (index == -1) return;
    final removed = widget.entries[index];
    final previousIndex = _selectedIndex;
    setState(() {
      widget.entries.removeAt(index);
      if (widget.entries.isEmpty) {
        widget.entries.add(_newBlankEntry());
      }
      _selectedIndex = index >= widget.entries.length
          ? widget.entries.length - 1
          : index;
      _loadEntry(_current);
    });

    if (removed.id == null) return;
    try {
      await widget.apiClient.delete('/notebook/notes/${removed.id}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final restoreIndex = index > widget.entries.length
            ? widget.entries.length
            : index;
        widget.entries.insert(restoreIndex, removed);
        _selectedIndex = previousIndex >= widget.entries.length
            ? widget.entries.length - 1
            : previousIndex;
        _loadEntry(_current);
      });
    }
  }

  int _findNoteIndex(NotebookNote note) {
    return widget.entries.indexWhere(
      (entry) =>
          note.id == null ? entry.title == note.title : entry.id == note.id,
    );
  }

  Future<void> _saveCurrent() async {
    _current.title = _titleController.text.trim().isEmpty
        ? 'Untitled note'
        : _titleController.text.trim();
    _current.plan = _planController.text.trim();
    _current.note = _noteController.text.trim();
    _current.updatedAt = 'saved now';
    _current.saved = true;
    setState(() {});

    try {
      final response = _current.id == null
          ? await widget.apiClient.postJson(
              '/notebook/notes',
              _current.toJson(accountId: ActiveAccountSession.accountId),
            )
          : await widget.apiClient.patchJson(
              '/notebook/notes/${_current.id}',
              _current.toJson(accountId: ActiveAccountSession.accountId),
            );
      final saved = _NotebookEntry.fromJson(response as Map<String, dynamic>);
      final index = widget.entries.indexOf(_current);
      if (index != -1) {
        widget.entries[index] = saved;
        _selectedIndex = index;
        _loadEntry(saved);
      }
      setState(() {});
    } catch (_) {
      _current.saved = false;
      setState(() {});
    }
  }

  void _markDirty() {
    if (!_current.saved) return;
    setState(() {
      _current.saved = false;
    });
  }

  Future<void> _persistEntry(_NotebookEntry entry) async {
    try {
      final response = entry.id == null
          ? await widget.apiClient.postJson(
              '/notebook/notes',
              entry.toJson(accountId: ActiveAccountSession.accountId),
            )
          : await widget.apiClient.patchJson(
              '/notebook/notes/${entry.id}',
              entry.toJson(accountId: ActiveAccountSession.accountId),
            );
      final saved = _NotebookEntry.fromJson(response as Map<String, dynamic>);
      final index = widget.entries.indexOf(entry);
      if (index != -1) {
        widget.entries[index] = saved;
        if (index == _selectedIndex) {
          _loadEntry(saved);
        }
      }
    } catch (_) {
      entry.pinned = !entry.pinned;
      entry.saved = false;
    }
  }

  void _addTask() {
    final text = _taskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _current.tasks.add(_NotebookTask(text));
      _taskController.clear();
      _current.saved = false;
    });
  }

  void _addTaskPreset(List<String> tasks) {
    setState(() {
      for (final task in tasks) {
        final exists = _current.tasks.any(
          (item) => item.text.toLowerCase() == task.toLowerCase(),
        );
        if (!exists) {
          _current.tasks.add(_NotebookTask(task));
        }
      }
      _current.saved = false;
    });
  }

  void _clearDoneTasks() {
    setState(() {
      _current.tasks.removeWhere((task) => task.done);
      _current.saved = false;
    });
  }

  void _toggleTask(int index) {
    setState(() {
      _current.tasks[index].done = !_current.tasks[index].done;
      _current.saved = false;
    });
  }

  void _deleteTask(int index) {
    setState(() {
      _current.tasks.removeAt(index);
      _current.saved = false;
    });
  }
}

class _NotebookEditor extends StatelessWidget {
  final _NotebookEntry entry;
  final TextEditingController titleController;
  final TextEditingController planController;
  final TextEditingController noteController;
  final TextEditingController taskController;
  final VoidCallback onSave;
  final VoidCallback onChanged;
  final VoidCallback onAddTask;
  final ValueChanged<List<String>> onAddTaskPreset;
  final VoidCallback onClearDoneTasks;
  final ValueChanged<int> onToggleTask;
  final ValueChanged<int> onDeleteTask;

  const _NotebookEditor({
    required this.entry,
    required this.titleController,
    required this.planController,
    required this.noteController,
    required this.taskController,
    required this.onSave,
    required this.onChanged,
    required this.onAddTask,
    required this.onAddTaskPreset,
    required this.onClearDoneTasks,
    required this.onToggleTask,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: 820),
      padding: EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(entry.icon, size: 18, color: entry.accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.template,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _SaveBadge(saved: entry.saved),
              SizedBox(width: 8),
              FilledButton(
                onPressed: onSave,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.save, size: 14),
                    SizedBox(width: 7),
                    Text(strings.text('Save')),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          TextBox(
            controller: titleController,
            placeholder: strings.text('Note title'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            onChanged: (_) => onChanged(),
          ),
          SizedBox(height: 16),
          _SectionLabel(
            icon: FluentIcons.bulleted_list,
            label: strings.text('Planning'),
          ),
          SizedBox(height: 8),
          _TextToolsBar(controller: planController, onChanged: onChanged),
          SizedBox(height: 8),
          TextBox(
            controller: planController,
            placeholder: strings.text(
              'Bias, risk, trigger, invalidation, action plan...',
            ),
            maxLines: 6,
            onChanged: (_) => onChanged(),
          ),
          SizedBox(height: 16),
          _SectionLabel(
            icon: FluentIcons.check_list,
            label: strings.text('Checklist'),
          ),
          SizedBox(height: 8),
          _ChecklistToolsBar(
            onAddTaskPreset: onAddTaskPreset,
            onClearDoneTasks: onClearDoneTasks,
          ),
          SizedBox(height: 8),
          ...entry.tasks.asMap().entries.map(
            (task) => _TaskRow(
              task: task.value,
              onToggle: () => onToggleTask(task.key),
              onDelete: () => onDeleteTask(task.key),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: taskController,
                  placeholder: strings.text('Add planning task'),
                  onSubmitted: (_) => onAddTask(),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                icon: Icon(FluentIcons.add, size: 14),
                onPressed: onAddTask,
              ),
            ],
          ),
          SizedBox(height: 16),
          _SectionLabel(
            icon: FluentIcons.edit_note,
            label: strings.text('Notes'),
          ),
          SizedBox(height: 8),
          _TextToolsBar(controller: noteController, onChanged: onChanged),
          SizedBox(height: 8),
          TextBox(
            controller: noteController,
            placeholder: strings.text(
              'Capture ideas, lessons, scenarios, review notes...',
            ),
            maxLines: 12,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _TextToolsBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _TextToolsBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _ToolButton(
          icon: FluentIcons.header2,
          label: strings.text('Heading'),
          onPressed: () => _insertLine(controller, '## ', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.bulleted_list,
          label: strings.text('Bullet'),
          onPressed: () => _insertLine(controller, '- ', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.numbered_list,
          label: strings.text('Numbered'),
          onPressed: () => _insertLine(controller, '1. ', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.check_list,
          label: strings.text('Checkbox'),
          onPressed: () => _insertLine(controller, '- [ ] ', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.quotes,
          label: strings.text('Quote'),
          onPressed: () => _insertLine(controller, '> ', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.bold,
          label: strings.text('Bold'),
          onPressed: () => _wrapSelection(controller, '**', '**', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.italic,
          label: strings.text('Italic'),
          onPressed: () => _wrapSelection(controller, '_', '_', onChanged),
        ),
        _ToolButton(
          icon: FluentIcons.clock,
          label: strings.text('Timestamp'),
          onPressed: () => _insertText(controller, _timestamp(), onChanged),
        ),
      ],
    );
  }
}

class _ChecklistToolsBar extends StatelessWidget {
  final ValueChanged<List<String>> onAddTaskPreset;
  final VoidCallback onClearDoneTasks;

  const _ChecklistToolsBar({
    required this.onAddTaskPreset,
    required this.onClearDoneTasks,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PresetButton(
          icon: FluentIcons.calendar_day,
          label: strings.text('Pre-market'),
          onPressed: () => onAddTaskPreset([
            'Mark key levels',
            'Define invalidation',
            'Set max risk before entry',
          ]),
        ),
        _PresetButton(
          icon: FluentIcons.task_manager,
          label: strings.text('Trade review'),
          onPressed: () => onAddTaskPreset([
            'Screenshot entry and exit',
            'Tag mistake or rule followed',
            'Write one lesson',
          ]),
        ),
        _PresetButton(
          icon: FluentIcons.clear,
          label: strings.text('Clear done'),
          onPressed: onClearDoneTasks,
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        icon: Icon(icon, size: 14, color: AppColors.textSecondary),
        onPressed: onPressed,
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _PresetButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onPressed,
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.primary),
          SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.primary),
        SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  final _NotebookTask task;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskRow({
    required this.task,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Checkbox(checked: task.done, onChanged: (_) => onToggle()),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              task.text,
              style: TextStyle(
                color: task.done
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                decoration: task.done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            icon: Icon(FluentIcons.delete, size: 13),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _SaveBadge extends StatelessWidget {
  final bool saved;

  const _SaveBadge({required this.saved});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    final color = saved ? AppColors.success : AppColors.warning;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        saved ? strings.text('Saved') : strings.text('Draft'),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _NotebookEntry {
  int? id;
  String title;
  String template;
  String plan;
  String note;
  String updatedAt;
  bool pinned;
  bool saved;
  IconData icon;
  Color accent;
  String iconKey;
  String accentKey;
  final List<_NotebookTask> tasks;

  _NotebookEntry({
    this.id,
    required this.title,
    required this.template,
    required this.plan,
    required this.note,
    required this.updatedAt,
    required this.icon,
    required this.accent,
    required this.tasks,
    this.iconKey = 'edit_note',
    this.accentKey = 'primary',
    this.pinned = false,
    this.saved = true,
  });

  factory _NotebookEntry.fromJson(Map<String, dynamic> json) {
    final iconKey = json['icon_key'] as String? ?? 'edit_note';
    final accentKey = json['accent_key'] as String? ?? 'primary';
    final tasks = (json['tasks'] as List<dynamic>? ?? [])
        .map((item) => _NotebookTask.fromJson(item as Map<String, dynamic>))
        .toList();
    return _NotebookEntry(
      id: json['id'] as int?,
      title: json['title'] as String? ?? 'Untitled note',
      template: json['template'] as String? ?? 'Blank Note',
      plan: json['plan'] as String? ?? '',
      note: json['note'] as String? ?? '',
      updatedAt: _formatUpdatedAt(json['updated_at'] as String?),
      pinned: json['pinned'] as bool? ?? false,
      saved: json['saved'] as bool? ?? true,
      icon: _iconFromKey(iconKey),
      accent: _accentFromKey(accentKey),
      iconKey: iconKey,
      accentKey: accentKey,
      tasks: tasks,
    );
  }

  Map<String, dynamic> toJson({required int accountId}) {
    return {
      'account_id': accountId,
      'title': title,
      'template': template,
      'plan': plan,
      'note': note,
      'pinned': pinned,
      'saved': saved,
      'icon_key': iconKey,
      'accent_key': accentKey,
      'tasks': tasks.map((task) => task.toJson()).toList(),
    };
  }

  NotebookNote toNote() {
    return NotebookNote(
      id: id,
      title: title,
      preview: plan.isNotEmpty ? plan : note,
      date: updatedAt,
      icon: icon,
      color: accent,
      pinned: pinned,
    );
  }
}

class _NotebookTask {
  final String text;
  bool done;

  _NotebookTask(this.text, {this.done = false});

  factory _NotebookTask.fromJson(Map<String, dynamic> json) {
    return _NotebookTask(
      json['text'] as String? ?? '',
      done: json['done'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {'text': text, 'done': done};
  }
}

IconData _iconFromKey(String key) {
  return switch (key) {
    'pin' => FluentIcons.pin,
    'page_add' => FluentIcons.page_add,
    'lightbulb' => FluentIcons.lightbulb,
    'task_manager' => FluentIcons.task_manager,
    'heart' => FluentIcons.heart,
    'heart_fill' => FluentIcons.heart_fill,
    _ => FluentIcons.edit_note,
  };
}

Color _accentFromKey(String key) {
  return switch (key) {
    'danger' => AppColors.danger,
    'warning' => AppColors.warning,
    'success' => AppColors.success,
    _ => AppColors.primary,
  };
}

String _iconKeyFromTemplate(NotebookTemplate template) {
  return switch (template.title) {
    'Pre-Market Thesis' => 'lightbulb',
    'Trade Review' => 'task_manager',
    'Emotional Mapping Journal' => 'heart',
    'Pre-Market Mental Prep' => 'heart_fill',
    _ => 'edit_note',
  };
}

String _accentKeyFromColor(Color color) {
  if (color == AppColors.danger) return 'danger';
  if (color == AppColors.warning) return 'warning';
  if (color == AppColors.success) return 'success';
  return 'primary';
}

String _formatUpdatedAt(String? value) {
  if (value == null || value.isEmpty) return 'saved now';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}/$month/$day';
}

void _insertLine(
  TextEditingController controller,
  String prefix,
  VoidCallback onChanged,
) {
  final text = controller.text;
  final selection = controller.selection;
  final index = selection.isValid ? selection.start : text.length;
  final safeIndex = index.clamp(0, text.length);
  final needsBreak = safeIndex > 0 && text[safeIndex - 1] != '\n';
  _insertText(controller, needsBreak ? '\n$prefix' : prefix, onChanged);
}

void _insertText(
  TextEditingController controller,
  String insertion,
  VoidCallback onChanged,
) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  final safeStart = start.clamp(0, value.text.length);
  final safeEnd = end.clamp(0, value.text.length);
  final nextText = value.text.replaceRange(safeStart, safeEnd, insertion);
  final nextOffset = safeStart + insertion.length;
  controller.value = value.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: TextRange.empty,
  );
  onChanged();
}

void _wrapSelection(
  TextEditingController controller,
  String before,
  String after,
  VoidCallback onChanged,
) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  final safeStart = start.clamp(0, value.text.length);
  final safeEnd = end.clamp(0, value.text.length);
  final selected = value.text.substring(safeStart, safeEnd);
  final wrapped = '$before$selected$after';
  final nextText = value.text.replaceRange(safeStart, safeEnd, wrapped);
  final nextOffset = selected.isEmpty
      ? safeStart + before.length
      : safeStart + wrapped.length;
  controller.value = value.copyWith(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: TextRange.empty,
  );
  onChanged();
}

String _timestamp() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  return '[${now.year}/$month/$day $hour:$minute] ';
}

_NotebookEntry _newBlankEntry() {
  return _NotebookEntry(
    title: 'Untitled note',
    template: 'Blank Note',
    plan: '',
    note: '',
    updatedAt: 'now',
    icon: FluentIcons.page_add,
    accent: AppColors.primary,
    iconKey: 'page_add',
    accentKey: 'primary',
    saved: false,
    tasks: [_NotebookTask('Clarify the objective')],
  );
}

List<String> _orderedTemplateCategories(List<NotebookTemplate> templates) {
  final categories = <String>[];
  for (final template in templates) {
    if (!categories.contains(template.category)) {
      categories.add(template.category);
    }
  }
  return categories;
}
