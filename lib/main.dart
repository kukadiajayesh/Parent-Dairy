import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/prefs_service.dart';
import 'core/services/telemetry_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preferences are needed before the first frame: the theme and the remembered
  // child come from them, and reading them later would flash the wrong palette.
  await PrefsService.init();

  String? startupError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // §25. Firestore's cache is what makes a record saved with no signal appear
    // on the timeline immediately and sync later, so it is set explicitly
    // rather than left to the platform default.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    await Telemetry.init();
  } catch (error) {
    // A missing google-services.json or a Firebase API that has not been
    // enabled must not present as a white screen — the parent gets a real
    // message and the developer gets the reason (§32).
    startupError = error.toString();
  }

  runApp(ParentAcademicDiaryApp(startupError: startupError));
}
