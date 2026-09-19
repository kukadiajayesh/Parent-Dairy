import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/errors/app_failure.dart';
import '../../core/services/telemetry_service.dart';
import '../firestore_paths.dart';

/// Google-only parent authentication (§4).
///
/// The design's login screen offers exactly one button, so this repository does
/// too. Everything downstream keys off [uid]; adding email/password later means
/// adding methods here and nothing else.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, GoogleSignIn? google})
    : _auth = auth ?? FirebaseAuth.instance,
      _injectedGoogle = google;

  final FirebaseAuth _auth;
  final GoogleSignIn? _injectedGoogle;

  /// Resolved lazily: touching `GoogleSignIn.instance` reaches the platform
  /// channel, which must not happen in a test that never signs in.
  GoogleSignIn get _google => _injectedGoogle ?? GoogleSignIn.instance;

  bool _initialized = false;

  User? get currentUser => _auth.currentUser;
  String? get uid => _auth.currentUser?.uid;
  bool get isSignedIn => _auth.currentUser != null;

  /// Fires on sign-in, sign-out and token refresh — what the splash screen
  /// waits on to decide where to send the parent.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Must run once before [signInWithGoogle]. On Android the client id comes
  /// from the `default_web_client_id` resource that the google-services Gradle
  /// plugin generates, so nothing is hardcoded here.
  ///
  /// Skipped on web: `google_sign_in_web` refuses `authenticate()` outright
  /// (it only supports its own `renderButton` widget), so web signs in
  /// through Firebase's own popup flow instead — see [signInWithGoogle].
  Future<void> ensureInitialized() async {
    if (_initialized || kIsWeb) return;
    try {
      await _google.initialize();
      _initialized = true;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      try {
        final credential = await _auth.signInWithPopup(GoogleAuthProvider());
        await _ensureUserDocument(credential.user!);
        await Telemetry.setUser(credential.user!.uid);
        unawaited(Telemetry.signIn());
        return credential;
      } on FirebaseAuthException catch (error) {
        if (error.code == 'popup-closed-by-user' ||
            error.code == 'cancelled-popup-request') {
          throw AppFailure.cancelled;
        }
        throw AppFailure(
          FailureKind.unknown,
          'Could not sign in with Google. Please try again.',
          cause: error,
        );
      } catch (error) {
        throw AppFailure.from(error);
      }
    }

    await ensureInitialized();
    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AppFailure(
          FailureKind.unknown,
          'Google did not return a sign-in token. Please try again.',
        );
      }

      final credential = await _auth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      await _ensureUserDocument(credential.user!);
      await Telemetry.setUser(credential.user!.uid);
      unawaited(Telemetry.signIn());
      return credential;
    } on GoogleSignInException catch (error) {
      // Backing out of the account chooser is not an error worth a toast.
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw AppFailure.cancelled;
      }
      throw AppFailure(
        FailureKind.unknown,
        'Could not sign in with Google. Please try again.',
        cause: error,
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Restores a session silently at launch when the platform can. On web,
  /// `FirebaseAuth`'s own persisted session already covers this — there is no
  /// separate Google-side session to restore.
  Future<void> attemptSilentSignIn() async {
    if (isSignedIn || kIsWeb) return;
    try {
      await ensureInitialized();
      await _google.attemptLightweightAuthentication();
    } catch (_) {
      // Never block the splash screen on a best-effort restore.
    }
  }

  Future<void> signOut() async {
    try {
      unawaited(Telemetry.signOut());
      await _google.signOut();
      await _auth.signOut();
      await Telemetry.setUser(null);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// The parent profile document. Written on every sign-in so a changed Google
  /// display name or avatar follows the account, and merged so nothing else in
  /// the document is clobbered.
  Future<void> _ensureUserDocument(User user) async {
    try {
      final ref = Paths.user(user.uid);
      final existing = await ref.get();
      await ref.set({
        'uid': user.uid,
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL,
        'lastSignInAt': FieldValue.serverTimestamp(),
        // Only stamped on first sign-in — a merge that always wrote this would
        // reset the account's age on every launch.
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      // A profile write failing must not strand a parent on the login screen;
      // the document is re-attempted on the next sign-in.
      unawaited(
        Telemetry.recordError(
          AppFailure.from(error),
          StackTrace.current,
          context: 'ensureUserDocument',
        ),
      );
    }
  }
}
