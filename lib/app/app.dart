import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/image_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/share_intent_service.dart';
import '../core/theme/app_theme.dart';
import '../data/app_state.dart';
import '../features/share/share_image_page.dart';
import 'routes.dart';
import 'startup_error_page.dart';

class ParentAcademicDiaryApp extends StatefulWidget {
  const ParentAcademicDiaryApp({super.key, this.startupError});

  /// Non-null when `Firebase.initializeApp` failed. The app still runs so the
  /// parent sees an explanation rather than a blank screen.
  final String? startupError;

  @override
  State<ParentAcademicDiaryApp> createState() => _ParentAcademicDiaryAppState();
}

class _ParentAcademicDiaryAppState extends State<ParentAcademicDiaryApp>
    with WidgetsBindingObserver {
  final AppState _state = AppState();
  final ShareIntentService _share = ShareIntentService();
  final NotificationService _notifications = NotificationService.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Files shared in before the parent was signed in or had a child. Held so
  /// the share is honoured once they are, rather than silently dropped.
  List<PickedAttachment> _heldShare = const [];

  /// Whether the OS notification permission has been granted. Requested once
  /// at startup now that reminders have no settings-screen toggle of their
  /// own to trigger the prompt.
  bool _notificationsGranted = false;
  bool _remindersResynced = false;

  /// Whether this sign-in has already drained the notice buffer and run the
  /// retention purge. Reset when the user changes.
  String? _noticesStartedFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startupError == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    await _state.bootstrap();
    await _notifications.init();
    _state.addListener(_onStateChanged);
    _share.incoming.addListener(_onSharedFiles);
    _notifications.tapped.addListener(_onNotificationTapped);
    await _share.start();
    unawaited(_requestNotificationPermission());
    _onNotificationTapped();
  }

  /// Prompt 03 §B: the listener buffers while Flutter is not running, so
  /// every return to the foreground re-checks the permission and drains.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _state.authStatus == AuthStatus.ready) {
      unawaited(_state.refreshNoticeCapture());
    }
  }

  /// A tapped reminder opens what it was about: a worksheet, or a notice.
  /// Held until the parent is signed in with a child, like a share.
  void _onNotificationTapped() {
    final payload = _notifications.tapped.value;
    if (payload == null || payload.isEmpty) return;
    if (_state.authStatus != AuthStatus.ready) return;
    _notifications.tapped.value = null;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (payload.startsWith(NotificationService.noticePayloadPrefix)) {
      navigator.pushNamed(
        Routes.noticeDetail,
        arguments: payload.substring(NotificationService.noticePayloadPrefix.length),
      );
    } else {
      navigator.pushNamed(Routes.worksheetDetail, arguments: payload);
    }
  }

  Future<void> _requestNotificationPermission() async {
    _notificationsGranted = await _notifications.requestPermission();
    if (_notificationsGranted && _state.authStatus == AuthStatus.ready) {
      _remindersResynced = true;
      unawaited(_notifications.resyncAll(_state.pendingWorksheets));
    }
  }

  void _onStateChanged() {
    // A share that arrived before sign-in becomes deliverable the moment the
    // parent has an account and a child.
    if (_heldShare.isNotEmpty && _state.authStatus == AuthStatus.ready) {
      final files = _heldShare;
      _heldShare = const [];
      _openQuickAdd(files);
    }
    // Re-arms every pending worksheet's reminder the first time both
    // permission and the parent's records are available — whichever lands
    // second.
    if (!_remindersResynced &&
        _notificationsGranted &&
        _state.authStatus == AuthStatus.ready) {
      _remindersResynced = true;
      unawaited(_notifications.resyncAll(_state.pendingWorksheets));
    }
    // Once per sign-in: drain whatever the listener buffered while the app
    // was closed, and drop notices past the retention window.
    if (_state.authStatus == AuthStatus.ready &&
        _noticesStartedFor != _state.uid) {
      _noticesStartedFor = _state.uid;
      unawaited(_state.refreshNoticeCapture());
      unawaited(_state.purgeOldNotices());
      _onNotificationTapped();
    }
  }

  void _onSharedFiles() {
    final files = _share.incoming.value;
    if (files.isEmpty) return;
    _share.consume();

    if (_state.authStatus != AuthStatus.ready) {
      _heldShare = files;
      return;
    }
    _openQuickAdd(files);
  }

  void _openQuickAdd(List<PickedAttachment> files) {
    _navigatorKey.currentState?.pushNamed(
      Routes.shareChooser,
      arguments: ShareImageArgs(files: files),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _state.removeListener(_onStateChanged);
    _share.incoming.removeListener(_onSharedFiles);
    _notifications.tapped.removeListener(_onNotificationTapped);
    unawaited(_share.dispose());
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.startupError;

    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          title: 'Parent Academic Diary',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _state.themeMode,
          home: error == null ? null : StartupErrorPage(detail: error),
          initialRoute: error == null ? Routes.splash : null,
          onGenerateRoute: error == null ? Routes.onGenerateRoute : null,
          // Baseline system-bar styling for the whole app, so status-bar icons
          // stay legible against the page background. The few dark screens
          // (splash, picker, viewer) override this with their own region.
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: MediaQuery.platformBrightnessOf(context) == Brightness.dark
                ? _darkOverlay
                : _lightOverlay,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Dark glyphs for the light palette's cream background.
const _lightOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
);

/// Light glyphs for the dark palette.
const _darkOverlay = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
);
