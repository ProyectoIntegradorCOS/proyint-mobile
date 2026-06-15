import 'dart:async';

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 18:12 UTC-5 (Lima)][desc: Extrae timers recurrentes del State para flush background, refresh de token y refrescos periódicos del mapa][obj: MapTimerManager]
class MapTimerManager {
  Timer? _pendingRouteRefreshTimer;
  Timer? _pendingSyncRefreshTimer;
  Timer? _backgroundFlushTimer;
  Timer? _tokenRefreshTimer;

  void startPendingRouteRefresh(Future<void> Function() onTick) {
    _pendingRouteRefreshTimer?.cancel();
    _pendingRouteRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(onTick()),
    );
  }

  void startPendingSyncRefresh(Future<void> Function() onTick) {
    _pendingSyncRefreshTimer?.cancel();
    _pendingSyncRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(onTick()),
    );
  }

  void startBackgroundFlush(Future<void> Function() onTick) {
    _backgroundFlushTimer?.cancel();
    _backgroundFlushTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(onTick()),
    );
  }

  void stopBackgroundFlush() {
    _backgroundFlushTimer?.cancel();
    _backgroundFlushTimer = null;
  }

  void startTokenRefresh(Future<void> Function() onTick) {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => unawaited(onTick()),
    );
  }

  void stopTokenRefresh() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  void dispose() {
    _pendingRouteRefreshTimer?.cancel();
    _pendingSyncRefreshTimer?.cancel();
    _backgroundFlushTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _pendingRouteRefreshTimer = null;
    _pendingSyncRefreshTimer = null;
    _backgroundFlushTimer = null;
    _tokenRefreshTimer = null;
  }
}
