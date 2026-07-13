import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'journal_chart_import_service.dart';
import 'journal_chart_preview_widgets.dart';
import 'journal_charts_panel.dart';
import 'journal_shared_widgets.dart';

class JournalChartToolCard extends StatefulWidget {
  final String timeframe;
  final List<JournalChartRef> refs;
  final ValueChanged<JournalChartRef> onAdd;
  final ValueChanged<JournalChartRef> onDelete;

  const JournalChartToolCard({
    super.key,
    required this.timeframe,
    required this.refs,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<JournalChartToolCard> createState() => _JournalChartToolCardState();
}

class _JournalChartToolCardState extends State<JournalChartToolCard> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalSectionLabel(widget.timeframe),
        Container(
          constraints: const BoxConstraints(minHeight: 184),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.shellBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.refs.isEmpty)
                const JournalEmptyChartState()
              else
                ...widget.refs.map(
                  (ref) => JournalChartRefTile(
                    ref: ref,
                    onDelete: () => widget.onDelete(ref),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Button(
                      onPressed: _busy ? null : _pasteImageFromClipboard,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FluentIcons.paste, size: 12),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Paste',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Button(
                      onPressed: _busy ? null : _chooseImageFromFolder,
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(FluentIcons.folder_open, size: 12),
                          SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Choose',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Importing...',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _addChartPath(String path, {String? note}) {
    widget.onAdd(
      JournalChartRef(
        timeframe: widget.timeframe,
        path: path,
        note: note ?? '',
      ),
    );
  }

  Future<void> _chooseImageFromFolder() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await JournalChartImageImportService.pickImagePath();
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final stored = await JournalChartImageImportService.copyToChartStorage(
        picked,
        widget.timeframe,
      );
      _addChartPath(stored.path);
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pasteImageFromClipboard() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stored = await JournalChartImageImportService.saveClipboardImage(
        widget.timeframe,
      );
      _addChartPath(stored.path);
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }
}
