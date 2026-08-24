import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Watches the device's network state so the shell can show the design's
/// offline banner (§25) rather than a toggle that only ever moved by hand.
///
/// This reports *reachability of a network*, not of Firebase. A record saved
/// while this says "online" can still be queued by Firestore; attachment
/// upload state is tracked separately on the record itself.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  /// A service that never touches the platform channel, for tests and for the
  /// design-states gallery.
  ConnectivityService.fixed({bool offline = false}) : _connectivity = null {
    this.offline.value = offline;
  }

  final Connectivity? _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  final ValueNotifier<bool> offline = ValueNotifier<bool>(false);

  Future<void> start() async {
    final connectivity = _connectivity;
    if (connectivity == null) return;
    try {
      offline.value = _isOffline(await connectivity.checkConnectivity());
    } catch (_) {
      // A platform that cannot answer is treated as online: showing a false
      // "no internet" banner is worse than showing none.
      offline.value = false;
    }
    _sub = connectivity.onConnectivityChanged.listen(
      (results) => offline.value = _isOffline(results),
      onError: (_) => offline.value = false,
    );
  }

  static bool _isOffline(List<ConnectivityResult> results) =>
      results.isEmpty || results.every((r) => r == ConnectivityResult.none);

  Future<void> dispose() async {
    await _sub?.cancel();
    offline.dispose();
  }
}
