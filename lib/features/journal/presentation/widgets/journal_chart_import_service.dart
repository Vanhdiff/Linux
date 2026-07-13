import 'dart:io';

class JournalChartImageImportService {
  static Future<String?> pickImagePath() async {
    if (!Platform.isWindows) {
      throw Exception('Image picker is currently available on Windows only.');
    }
    final resultFile = File(
      '${Directory.systemTemp.path}\\trading_desk_chart_pick_${DateTime.now().microsecondsSinceEpoch}.txt',
    );
    final resultPath = _psLiteral(resultFile.path);
    const script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Filter = "Image files|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.webp|All files|*.*"
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  [System.IO.File]::WriteAllText(RESULT_PATH, \$dialog.FileName, [System.Text.Encoding]::UTF8)
}
''';
    final resolvedScript = script.replaceFirst('RESULT_PATH', resultPath);
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-STA',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        resolvedScript,
      ]);
      if (result.exitCode != 0) {
        throw Exception('Could not open image picker.');
      }
      if (!await resultFile.exists()) return null;
      final output = (await resultFile.readAsString()).trim();
      if (output.isEmpty) return null;
      return cleanPath(output);
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
    final cleanSourcePath = cleanPath(sourcePath);
    final source = File(cleanSourcePath);
    if (!await source.exists()) {
      throw Exception('Selected image does not exist: $cleanSourcePath');
    }
    final target = targetFile(timeframe, extension(cleanSourcePath));
    await source.copy(target.path);
    return target;
  }

  static Future<File> saveClipboardImage(String timeframe) async {
    if (!Platform.isWindows) {
      throw Exception(
        'Clipboard image paste is currently available on Windows only.',
      );
    }
    final target = targetFile(timeframe, '.png');
    final targetPath = _psLiteral(target.path);
    const script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$image = [System.Windows.Forms.Clipboard]::GetImage()
if (\$null -ne \$image) {
  \$image.Save(TARGET_PATH, [System.Drawing.Imaging.ImageFormat]::Png)
  exit 0
}
if ([System.Windows.Forms.Clipboard]::ContainsFileDropList()) {
  \$files = [System.Windows.Forms.Clipboard]::GetFileDropList()
  foreach (\$file in \$files) {
    \$extension = [System.IO.Path]::GetExtension(\$file).ToLowerInvariant()
    if (@(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp") -contains \$extension) {
      Copy-Item -LiteralPath \$file -Destination TARGET_PATH -Force
      exit 0
    }
  }
}
exit 2
''';
    final resolvedScript = script.replaceAll('TARGET_PATH', targetPath);
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-STA',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      resolvedScript,
    ]);
    if (result.exitCode == 2) {
      throw Exception('Clipboard does not contain an image.');
    }
    if (result.exitCode != 0 || !await target.exists()) {
      throw Exception('Could not paste image from clipboard.');
    }
    return target;
  }

  static String cleanPath(String value) {
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

  static File targetFile(String timeframe, String extension) {
    final directory = chartStorageDirectory();
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    final cleanTimeframe = timeframe.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return File('${directory.path}\\${cleanTimeframe}_$timestamp$extension');
  }

  static Directory chartStorageDirectory() {
    final root =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return Directory('$root\\TradingDesk\\journal_charts');
  }

  static String extension(String path) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex == -1) return '.png';
    final result = fileName.substring(dotIndex).toLowerCase();
    return imageExtensions.contains(result) ? result : '.png';
  }

  static String _psLiteral(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}

bool journalChartCanPreviewImage(String path) {
  if (journalChartIsWebImage(path)) return true;
  final ext = JournalChartImageImportService.extension(path);
  return imageExtensions.contains(ext) && File(path).existsSync();
}

bool journalChartIsWebImage(String path) {
  final lower = path.toLowerCase();
  return lower.startsWith('http://') || lower.startsWith('https://');
}

const imageExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp'};
