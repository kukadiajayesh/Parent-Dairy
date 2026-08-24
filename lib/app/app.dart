import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../data/app_state.dart';
import 'routes.dart';

class ParentAcademicDiaryApp extends StatefulWidget {
  const ParentAcademicDiaryApp({super.key});

  @override
  State<ParentAcademicDiaryApp> createState() => _ParentAcademicDiaryAppState();
}

class _ParentAcademicDiaryAppState extends State<ParentAcademicDiaryApp> {
  final AppState _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          title: 'Parent Academic Diary',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _state.themeMode,
          initialRoute: Routes.splash,
          onGenerateRoute: Routes.onGenerateRoute,
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
