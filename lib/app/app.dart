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

class _ParentAcademicDiaryAppState extends State<ParentAcademicDiaryApp> {
  final AppState _state = AppState();
  final ShareIntentService _share = ShareIntentService();
  final NotificationService _notifications = NotificationService.instance;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Files shared in before the parent was signed in or had a child. Held so
  /// the share is honoured once they are, rather than silently dropped.
  List<PickedAttachment> _heldShare = const [];

  @override
  void initState() {
    super.initState();
    if (widget.startupError == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    await _state.bootstrap();
    await _notifications.init();
    _state.addListener(_onStateChanged);
    _share.incoming.addListener(_onSharedFiles);
    await _share.start();
  }

  void _onStateChanged() {
    // A share that arrived before sign-in becomes deliverable the moment the
    // parent has an account and a child.
    if (_heldShare.isNotEmpty && _state.authStatus == AuthStatus.ready) {
      final files = _heldShare;
      _heldShare = const [];
      _openQuickAdd(files);
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
      Routes.shareImage,
      arguments: ShareImageArgs(files: files),
    );
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _share.incoming.removeListener(_onSharedFiles);
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
            value: _state.isDark ? _darkOverlay : _lightOverlay,
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
