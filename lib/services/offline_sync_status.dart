import 'package:flutter/foundation.dart';

class OfflineSyncStatus extends ChangeNotifier {
  bool _syncing = false;
  bool _hasPending = false;
  bool _backendAvailable = true;
  DateTime? _lastBackendCheckAt;
  DateTime? _lastCompletedAt;
  bool _lastHadPending = false;

  bool get syncing => _syncing;
  bool get hasPending => _hasPending;
  bool get backendAvailable => _backendAvailable;
  DateTime? get lastBackendCheckAt => _lastBackendCheckAt;
  DateTime? get lastCompletedAt => _lastCompletedAt;
  bool get lastHadPending => _lastHadPending;

  void setSyncing(bool value, {bool? hasPending}) {
    if (_syncing == value && hasPending == null) return;
    _syncing = value;
    if (hasPending != null) {
      _hasPending = hasPending;
    }
    notifyListeners();
  }

  void setBackendAvailable(bool value) {
    if (_backendAvailable == value) {
      _lastBackendCheckAt = DateTime.now();
      return;
    }
    _backendAvailable = value;
    _lastBackendCheckAt = DateTime.now();
    notifyListeners();
  }

  void markCompleted({required bool hadPending}) {
    _lastCompletedAt = DateTime.now();
    _lastHadPending = hadPending;
    _hasPending = false;
    notifyListeners();
  }
}
