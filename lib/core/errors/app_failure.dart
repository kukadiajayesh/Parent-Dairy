import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';

/// What went wrong, in terms the UI can act on.
enum FailureKind {
  offline,
  permission,
  notFound,
  cancelled,
  quota,
  invalidFile,
  fileTooLarge,
  sessionExpired,
  unknown,
}

/// A failure with a message already fit to show a parent.
///
/// Every repository throws this rather than letting a `FirebaseException`
/// reach the widget layer, so screens never have to know which SDK failed
/// (§32).
class AppFailure implements Exception {
  const AppFailure(this.kind, this.message, {this.cause, this.canRetry = true});

  final FailureKind kind;
  final String message;
  final Object? cause;
  final bool canRetry;

  /// True when the parent simply backed out — the UI should stay silent.
  bool get isCancellation => kind == FailureKind.cancelled;

  static const cancelled = AppFailure(
    FailureKind.cancelled,
    'Cancelled',
    canRetry: false,
  );

  /// Normalises anything thrown below the repository layer.
  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;

    if (error is FirebaseAuthException) {
      return AppFailure(
        switch (error.code) {
          'network-request-failed' => FailureKind.offline,
          'user-disabled' || 'user-not-found' => FailureKind.sessionExpired,
          'requires-recent-login' => FailureKind.sessionExpired,
          _ => FailureKind.unknown,
        },
        switch (error.code) {
          'network-request-failed' =>
            'No internet connection. Check your network and try again.',
          'account-exists-with-different-credential' =>
            'That email is already signed in with a different method.',
          'user-disabled' => 'This account has been disabled.',
          'requires-recent-login' => 'Please sign in again to continue.',
          'popup-closed-by-user' || 'canceled' => 'Sign-in was cancelled.',
          _ => 'Could not sign in. Please try again.',
        },
        cause: error,
      );
    }

    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' || 'unauthorized' => AppFailure(
          FailureKind.permission,
          "You don't have access to this record.",
          cause: error,
          canRetry: false,
        ),
        'unavailable' || 'network-request-failed' || 'retry-limit-exceeded' =>
          AppFailure(
            FailureKind.offline,
            'No internet connection. Your changes are saved and will sync '
                'automatically.',
            cause: error,
          ),
        'not-found' || 'object-not-found' => AppFailure(
          FailureKind.notFound,
          'That file is no longer available.',
          cause: error,
          canRetry: false,
        ),
        'canceled' => cancelled,
        'quota-exceeded' || 'resource-exhausted' => AppFailure(
          FailureKind.quota,
          'Storage limit reached. Remove some attachments and try again.',
          cause: error,
          canRetry: false,
        ),
        'invalid-argument' || 'invalid-checksum' => AppFailure(
          FailureKind.invalidFile,
          "That file couldn't be read. Try a different one.",
          cause: error,
          canRetry: false,
        ),
        _ => AppFailure(
          FailureKind.unknown,
          error.message ?? 'Something went wrong. Please try again.',
          cause: error,
        ),
      };
    }

    if (error is SocketException || error is TimeoutException) {
      return AppFailure(
        FailureKind.offline,
        'No internet connection. Check your network and try again.',
        cause: error,
      );
    }

    if (error is FileSystemException) {
      return AppFailure(
        FailureKind.invalidFile,
        "That file couldn't be read. Try a different one.",
        cause: error,
        canRetry: false,
      );
    }

    return AppFailure(
      FailureKind.unknown,
      'Something went wrong. Please try again.',
      cause: error,
    );
  }

  @override
  String toString() => 'AppFailure(${kind.name}: $message)';
}
