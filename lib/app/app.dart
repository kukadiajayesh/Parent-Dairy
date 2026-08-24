import 'package:flutter/material.dart';

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
        ),
      ),
    );
  }
}
