import 'dart:convert';
import 'dart:io';

import '../../../../app/services/backend/backend_process_service.dart';

class DataManagementService {
  final BackendProcessService _backend;

  DataManagementService({BackendProcessService? backend})
    : _backend = backend ?? BackendProcessService();

  Directory get _dataRoot {
    final localAppData =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return Directory('$localAppData\\TradingDesk');
  }

  Directory get _databaseDirectory => Directory('${_dataRoot.path}\\data');
  File get _databaseFile => File('${_databaseDirectory.path}\\trading_desk.db');
  Directory get _journalChartsDirectory =>
      Directory('${_dataRoot.path}\\journal_charts');

  Directory get _backupDirectory {
    final userProfile =
        Platform.environment['USERPROFILE'] ?? _dataRoot.parent.path;
    return Directory('$userProfile\\Documents\\TradingDesk\\Backups');
  }

  String get storageSummary =>
      'Database: ${_databaseFile.path}\nCharts: ${_journalChartsDirectory.path}';

  Future<String> createBackup() async {
    await _backend.shutdownBackend();

    final timestamp = _timestamp(DateTime.now());
    final staging = await _createTempDirectory(
      'trading_desk_backup_$timestamp',
    );
    final dataTarget = Directory('${staging.path}\\data');
    dataTarget.createSync(recursive: true);

    if (_databaseFile.existsSync()) {
      _databaseFile.copySync('${dataTarget.path}\\trading_desk.db');
    }

    if (_journalChartsDirectory.existsSync()) {
      _copyDirectorySync(
        _journalChartsDirectory,
        Directory('${staging.path}\\journal_charts'),
      );
    }

    final metadata = File('${staging.path}\\metadata.json');
    metadata.writeAsStringSync(
      JsonEncoder.withIndent('  ').convert({
        'created_at': DateTime.now().toIso8601String(),
        'database_path': _databaseFile.path,
        'includes_journal_charts': _journalChartsDirectory.existsSync(),
      }),
    );

    _backupDirectory.createSync(recursive: true);
    final outputPath =
        '${_backupDirectory.path}\\trading-desk-backup-$timestamp.zip';

    await _runPowerShell('''
Compress-Archive -Path ${_psLiteral('${staging.path}\\*')} -DestinationPath ${_psLiteral(outputPath)} -Force
''');

    await _backend.ensureRunning();
    return outputPath;
  }

  Future<String> restoreBackup({String? backupPath}) async {
    final selectedBackup = backupPath ?? await _pickBackupFile();
    if (selectedBackup == null) {
      throw Exception('Restore canceled.');
    }

    await _backend.shutdownBackend();

    final staging = await _createTempDirectory(
      'trading_desk_restore_${DateTime.now().microsecondsSinceEpoch}',
    );
    await _runPowerShell('''
Expand-Archive -LiteralPath ${_psLiteral(selectedBackup)} -DestinationPath ${_psLiteral(staging.path)} -Force
''');

    final restoredDb = File('${staging.path}\\data\\trading_desk.db');
    if (!restoredDb.existsSync()) {
      throw Exception('Backup does not contain trading_desk.db.');
    }

    _databaseDirectory.createSync(recursive: true);
    restoredDb.copySync(_databaseFile.path);

    final restoredCharts = Directory('${staging.path}\\journal_charts');
    if (restoredCharts.existsSync()) {
      if (_journalChartsDirectory.existsSync()) {
        _journalChartsDirectory.deleteSync(recursive: true);
      }
      _copyDirectorySync(restoredCharts, _journalChartsDirectory);
    }

    await _backend.ensureRunning();
    return selectedBackup;
  }

  Future<void> openBackupFolder() async {
    _backupDirectory.createSync(recursive: true);
    await Process.run('explorer.exe', [_backupDirectory.path]);
  }

  void close() {
    _backend.close();
  }

  Future<Directory> _createTempDirectory(String name) async {
    final directory = Directory('${Directory.systemTemp.path}\\$name');
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
    directory.createSync(recursive: true);
    return directory;
  }

  Future<String?> _pickBackupFile() async {
    if (!Platform.isWindows) {
      throw Exception(
        'Backup restore picker is currently available on Windows only.',
      );
    }

    final script =
        '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Filter = "Trading Desk Backup (*.zip)|*.zip"
\$dialog.InitialDirectory = ${_psLiteral(_backupDirectory.path)}
\$dialog.CheckFileExists = \$true
\$dialog.Multiselect = \$false
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output \$dialog.FileName
}
''';

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);

    if (result.exitCode != 0) {
      throw Exception('Could not open backup picker.');
    }

    final output = '${result.stdout}'.trim();
    if (output.isEmpty) return null;
    return _cleanPath(output);
  }

  Future<void> _runPowerShell(String script) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      final error = '${result.stderr}'.trim();
      throw Exception(error.isEmpty ? 'PowerShell command failed.' : error);
    }
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      if (entity is File) {
        entity.copySync('${destination.path}\\${entity.uri.pathSegments.last}');
      } else if (entity is Directory) {
        _copyDirectorySync(
          entity,
          Directory('${destination.path}\\${entity.uri.pathSegments.last}'),
        );
      }
    }
  }

  String _timestamp(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$year$month$day-$hour$minute$second';
  }

  String _cleanPath(String value) {
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

  String _psLiteral(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }
}
