import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelemetryLogService {
  TelemetryLogService();
  String? _cachedPath;
  DateTime? _lastPurgeAt;
  static const int _logRetentionDays = 10;
  static const String _activeLogPathKey = 'active_log_path';

  Future<File> _resolveLogFile() async {
    if (_cachedPath == null) {
      final dir = await _documentsDir();
      final stamp = _peruTimestampForFilename();
      _cachedPath = '${dir.path}/log_${stamp}.txt';
      await _persistActiveLogPath(_cachedPath!);
    }
    return File(_cachedPath!);
  }

  Future<Directory> _documentsDir() async {
    if (Platform.isAndroid) {
      final shared = Directory('/storage/emulated/0/Documents');
      if (await shared.exists()) {
        return shared;
      }
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> log(String message) async {
    try {
      await _purgeOldLogsIfNeeded();
      final file = await _resolveLogFile();
      final ts = _peruTimestampForLog();
      await file.parent.create(recursive: true);
      await file.writeAsString('[$ts] $message\n', mode: FileMode.append);
    } catch (_) {}
  }

  Future<String?> logPath() async {
    try {
      final file = await _resolveLogFile();
      return file.path;
    } catch (_) {
      return null;
    }
  }

  String _peruTimestampForLog() {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$d/$m/$y $hh:$mm:$ss';
  }

  String _peruTimestampForFilename() {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 5));
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '${y}-${m}-${d}_${hh}-${mm}-${ss}';
  }

  Future<void> _persistActiveLogPath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeLogPathKey, path);
    } catch (_) {}
  }

  Future<void> _purgeOldLogsIfNeeded() async {
    final now = DateTime.now();
    if (_lastPurgeAt != null &&
        now.difference(_lastPurgeAt!).inHours < 24) {
      return;
    }
    _lastPurgeAt = now;
    try {
      final dir = await _documentsDir();
      if (!await dir.exists()) return;
      final cutoff = now.subtract(const Duration(days: _logRetentionDays));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (!name.startsWith('log_') || !name.endsWith('.txt')) continue;
        try {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }
}
