import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../api/api_client.dart';
import '../license/online_license_config.dart';
import '../license/online_license_models.dart';

class BackendProcessService {
  static Process? _process;
  final ApiClient _apiClient;

  BackendProcessService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  Future<void> ensureRunning() async {
    if (!_canStartBackend()) {
      if (await _isHealthy()) {
        await _shutdownBackend(closeClient: false);
      }
      throw StateError(
        'Backend is locked until the online license is activated and verified.',
      );
    }
    if (await _isHealthy()) return;
    if (_process != null) {
      _process = null;
    }
    if (_process == null) {
      final backendDir = _findBackendDir();
      final pythonExecutable = _findPythonExecutable(backendDir);
      _process = await Process.start(
        pythonExecutable,
        ['run.py'],
        workingDirectory: backendDir.path,
        mode: ProcessStartMode.detachedWithStdio,
        environment: {
          'LICENSE_MODE': OnlineLicenseConfig.enabled
              ? 'supabase'
              : 'offline',
        },
      );
      final process = _process!;
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
    }

    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (await _isHealthy()) return;
    }
    throw StateError('Backend did not start in time.');
  }

  bool _canStartBackend() {
    if (!OnlineLicenseConfig.enabled) {
      return true;
    }

    final session = _readStoredOnlineSession();
    if (session == null) {
      return false;
    }
    if (!session.isLicenseStillValid) {
      return false;
    }
    if (session.licenseKey.trim().isEmpty || session.accessToken.trim().isEmpty) {
      return false;
    }
    return true;
  }

  OnlineLicenseSession? _readStoredOnlineSession() {
    try {
      final file = File(_onlineSessionPath());
      if (!file.existsSync()) {
        return null;
      }
      final raw = file.readAsStringSync().trim();
      if (raw.isEmpty) {
        return null;
      }
      return OnlineLicenseSession.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  String _onlineSessionPath() {
    final appData =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        Directory.current.path;
    return '$appData${Platform.pathSeparator}TradingDesk'
        '${Platform.pathSeparator}license'
        '${Platform.pathSeparator}online_session.json';
  }

  Future<bool> _isHealthy() async {
    try {
      await _apiClient.getJson('/health');
      return true;
    } catch (_) {
      return false;
    }
  }

  Directory _findBackendDir() {
    final executableDir = File(Platform.resolvedExecutable).parent;
    final directCandidate = Directory(
      '${executableDir.path}${Platform.pathSeparator}backend',
    );
    final directRunFile = File(
      '${directCandidate.path}${Platform.pathSeparator}run.py',
    );
    if (directRunFile.existsSync()) return directCandidate;

    var current = Directory.current;
    for (var index = 0; index < 6; index++) {
      final candidate = Directory(
        '${current.path}${Platform.pathSeparator}backend',
      );
      final runFile = File('${candidate.path}${Platform.pathSeparator}run.py');
      if (runFile.existsSync()) return candidate;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    throw StateError(
      'Cannot find backend/run.py from ${Directory.current.path}.',
    );
  }

  String _findPythonExecutable(Directory backendDir) {
    final appDir = backendDir.parent;
    final bundledPython = File(
      '${appDir.path}${Platform.pathSeparator}python'
      '${Platform.pathSeparator}python.exe',
    );
    if (bundledPython.existsSync()) return bundledPython.path;

    final localVenvPython = File(
      '${backendDir.path}${Platform.pathSeparator}.venv'
      '${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe',
    );
    if (localVenvPython.existsSync()) return localVenvPython.path;

    final installerPython = File(
      '${appDir.path}${Platform.pathSeparator}installer'
      '${Platform.pathSeparator}python-runtime'
      '${Platform.pathSeparator}python.exe',
    );
    if (installerPython.existsSync()) return installerPython.path;

    return Platform.isWindows ? 'python.exe' : 'python';
  }

  void close() {
    _apiClient.close();
  }

  Future<void> shutdownBackend() async {
    await _shutdownBackend(closeClient: true);
  }

  Future<void> restart() async {
    await _shutdownBackend(closeClient: false);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    await ensureRunning();
  }

  Future<void> _shutdownBackend({required bool closeClient}) async {
    try {
      await _apiClient.postJson('/api/system/shutdown', {});
    } catch (_) {
      // Older backend versions do not expose shutdown; fall back to process kill.
    }

    final process = _process;
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
      }
      _process = null;
    }
    if (closeClient) {
      _apiClient.close();
    }
  }
}
