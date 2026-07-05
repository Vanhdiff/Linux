import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import 'journal_shared_widgets.dart';

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
                  child: _ChartToolCard(
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

class _ChartToolCard extends StatefulWidget {
  final String timeframe;
  final List<JournalChartRef> refs;
  final ValueChanged<JournalChartRef> onAdd;
  final ValueChanged<JournalChartRef> onDelete;

  const _ChartToolCard({
    required this.timeframe,
    required this.refs,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<_ChartToolCard> createState() => _ChartToolCardState();
}

class _ChartToolCardState extends State<_ChartToolCard> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalSectionLabel(widget.timeframe),
        Container(
          constraints: BoxConstraints(minHeight: 184),
          padding: EdgeInsets.all(10),
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
                _EmptyChartState()
              else
                ...widget.refs.map(
                  (ref) => _ChartRefTile(
                    ref: ref,
                    onDelete: () => widget.onDelete(ref),
                  ),
                ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Button(
                      onPressed: _busy ? null : _pasteImageFromClipboard,
                      child: Row(
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
                  SizedBox(width: 8),
                  Expanded(
                    child: Button(
                      onPressed: _busy ? null : _chooseImageFromFolder,
                      child: Row(
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
                SizedBox(height: 7),
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: ProgressRing(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
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
                SizedBox(height: 8),
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
      final picked = await _ChartImageImportService.pickImagePath();
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final stored = await _ChartImageImportService.copyToChartStorage(
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
      final stored = await _ChartImageImportService.saveClipboardImage(
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

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState();

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
          SizedBox(height: 6),
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

class _ChartRefTile extends StatelessWidget {
  final JournalChartRef ref;
  final VoidCallback onDelete;

  const _ChartRefTile({required this.ref, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canPreviewImage(ref.path)) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 88,
                width: double.infinity,
                child: _ImagePreview(ref.path),
              ),
            ),
            SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(FluentIcons.photo2, size: 14, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ref.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (ref.note.isNotEmpty) ...[
                      SizedBox(height: 4),
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
                icon: Icon(FluentIcons.delete, size: 13),
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final String path;

  const _ImagePreview(this.path);

  @override
  Widget build(BuildContext context) {
    if (_isWebImage(path)) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _BrokenImagePreview(),
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _BrokenImagePreview(),
    );
  }
}

class _BrokenImagePreview extends StatelessWidget {
  const _BrokenImagePreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(FluentIcons.photo_error, color: AppColors.textSecondary),
    );
  }
}

class _ChartImageImportService {
  static Future<String?> pickImagePath() async {
    if (!Platform.isWindows) {
      throw Exception('Image picker is currently available on Windows only.');
    }
    final resultFile = File(
      '${Directory.systemTemp.path}\\trading_desk_chart_pick_${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final resultPath = _psLiteral(resultFile.path);
    final script =
        '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Filter = "Image files|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|All files|*.*"
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [System.IO.File]::WriteAllText($resultPath, \$dialog.FileName, [System.Text.Encoding]::UTF8)
}
''';
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ]);
      if (result.exitCode != 0) {
        throw Exception('Could not open image picker.');
      }
      if (!await resultFile.exists()) return null;
      final output = (await resultFile.readAsString()).trim();
      if (output.isEmpty) return null;
      return _cleanPath(output);
    } finally {
      if (await resultFile.exists()) {
        await resultFile.delete();
      }
    }
  }

  static Future<File> copyToChartStorage(
    String sourcePath,
    String timeframe,
  ) async {
    final cleanSourcePath = _cleanPath(sourcePath);
    final source = File(cleanSourcePath);
    if (!await source.exists()) {
      throw Exception('Selected image does not exist: $cleanSourcePath');
    }
    final target = _targetFile(timeframe, _extension(cleanSourcePath));
    await source.copy(target.path);
    return target;
  }

  static Future<File> saveClipboardImage(String timeframe) async {
    if (!Platform.isWindows) {
      throw Exception(
        'Clipboard image paste is currently available on Windows only.',
      );
    }
    final target = _targetFile(timeframe, '.png');
    final targetPath = _psLiteral(target.path);
    final script =
        '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$image = [System.Windows.Forms.Clipboard]::GetImage()
if (\$null -ne \$image) {
  \$image.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
  exit 0
}
if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
  \$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
  foreach (\$file in \$files) {
    \$extension = [System.IO.Path]::GetExtension(\$file).ToLowerInvariant()
    if (@(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp") -contains \$extension) {
      Copy-Item -LiteralPath \$file -Destination $targetPath -Force
      exit 0
    }
  }
}
exit 2
''';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode == 2) {
      throw Exception('Clipboard does not contain an image.');
    }
    if (result.exitCode != 0 || !await target.exists()) {
      throw Exception('Could not paste image from clipboard.');
    }
    return target;
  }

  static String _cleanPath(String value) {
    final line = value
        .split(RegExp(r'[\r\n]+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .last;
    return line
        .replaceAll(
          RegExp(
            r'^["'
            "'"
            r']|["'
            "'"
            r']$',
          ),
          '',
        )
        .trim();
  }

  static File _targetFile(String timeframe, String extension) {
    final directory = _chartStorageDirectory();
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final cleanTimeframe = timeframe.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return File('${directory.path}\\${cleanTimeframe}_$timestamp$extension');
  }

  static Directory _chartStorageDirectory() {
    final root =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return Directory('$root\\TradingDesk\\journal_charts');
  }

  static String _extension(String path) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) return '.png';
    final extension = fileName.substring(dotIndex).toLowerCase();
    return _imageExtensions.contains(extension) ? extension : '.png';
  }

  static String _psLiteral(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

bool _canPreviewImage(String path) {
  if (_isWebImage(path)) return true;
  final extension = _ChartImageImportService._extension(path);
  return _imageExtensions.contains(extension) && File(path).existsSync();
}

bool _isWebImage(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};
