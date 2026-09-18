# 00 — Shared context

> Paste this block first in any session that implements one of the feature
> prompts. It is the contract the rest of them assume.

You are working in **Parent Academic Diary**, a Flutter app for parents that
keeps a child's worksheets, classwork and attachments on a date-wise academic
timeline, backed by Firebase.

## Stack

- Flutter, Dart SDK `^3.12.2`, Material 3, single target width 412dp (Android
  first, iOS builds but is not the primary surface).
- Firebase: Auth (Google sign-in), Firestore (`asia-south1`), Storage, FCM,
  Crashlytics, Analytics. Project `parent-academic-diary`, app id
  `com.parent.academic.diary`.
- Android: `minSdk 24`, `compileSdk 36` (plugin modules pinned — `android-37`
  does not resolve in this SDK release), core library desugaring **on**,
  multidex on.
- No state-management package. No code generation. No `build_runner`.

## Architecture — respect these seams

```
lib/
  app/            MaterialApp, theme wiring, Routes.onGenerateRoute, startup error
  core/
    config/       feature_flags.dart  (kShowExamMarks)
    errors/       app_failure.dart    every SDK exception → parent-readable text
    services/     prefs, connectivity, image, attachment actions, notifications,
                  share intents, telemetry, pdf thumbnails
    theme/        app_tokens.dart (ThemeExtension, light + dark), subject hues
    widgets/      the design system: buttons, chips, fields, layout, sheets,
                  states, toast, ImageSlot, StrokeIcon
  data/
    models.dart          pure Dart — NO Firebase import, every widget imports it
    mappers.dart         Firestore ⇄ model (class `Map$`)
    firestore_paths.dart every collection path (`Paths`), with the `Paths.db`
                         test seam
    repositories/        auth, child, subject, year, record, attachment, upload_queue
    app_state.dart       one ChangeNotifier (`AppState`) behind `AppScope`
  features/       one directory per screen family
  shell/          Home / Timeline / More frame and the Add sheet
```

### Non-negotiable conventions

1. **`models.dart` stays Firebase-free.** New models go there; their Firestore
   conversion goes in `mappers.dart`.
2. **Every collection path goes through `Paths`.** Never build a
   `FirebaseFirestore.instance.collection(...)` chain in a repository or a
   widget — tests swap `Paths.db` for a fake.
3. **Repositories throw `AppFailure`, never a raw `FirebaseException`.** Add a
   new `FailureKind` only if no existing kind fits (`offline, permission,
   notFound, cancelled, quota, invalidFile, fileTooLarge, sessionExpired,
   unknown`).
4. **Enums persist through a `wire` field**, never `name` — documents written
   by an older build must keep parsing. Mappers read defensively: a missing or
   wrong-typed field falls back, it never throws.
5. **Writes are soft.** Nothing user-visible is hard-deleted; set `isDeleted`
   and drop out of queries.
6. **Files are staged, not uploaded inline.** A record saves with its
   attachments marked `SyncState.pending` and a `localPath`; `UploadQueue`
   drains them when a network returns. Any new file-bearing feature uses the
   same path.
7. **UI uses the design system, not raw Material.** `AppFilledButton`,
   `AppTonalButton`, `AppOutlinedButton`, `AppIconButton`, `AppChip`,
   `SubjectChip`, `StatusPill`, `AppCard`, `SectionLabel`, `SettingsGroup`,
   `SettingsRow`, `AppTextField`, `PickerField`, `AppSwitch`, `AppSheet`,
   `EmptyStateView`, `ErrorStateView`, `InlineErrorBanner`, `Skeletons`,
   `AppToast`. Icons are `StrokeIcon(AppIcons.x)` — add new 24×24 stroked paths
   to `app_icons.dart` rather than reaching for `Icons.`.
8. **Colours come from `context.t`** (`AppTokens`). Never hardcode a hex in a
   widget; if a token is missing, add it to both `AppTokens.light` and
   `AppTokens.dark`.
9. **`AppState`'s existing read surface does not change.** Add to it; do not
   rename or re-shape `records`, `subjects`, `activeChild`, `groupBySubject`, …
10. **Routes** are registered in `Routes` and dispatched from
    `Routes.onGenerateRoute`. Full-screen destinations go there; tab-local ones
    are pushed inside `MainShell`.
11. **Comments explain *why*, not *what*.** Match the existing tone — the
    codebase documents trade-offs, not syntax.

## Tests

`flutter test` currently passes with 86 tests and no network. Firebase is faked
with `fake_cloud_firestore` and `firebase_auth_mocks`; `Paths.db` is the seam.
Widget tests pin the viewport to **411.4dp** — a horizontal overflow fits
exactly at 432dp and stays invisible. `testWidgets` fakes the clock, so anything
waiting on a Firestore stream runs inside `tester.runAsync`.

**Do not break the existing suite.** Every new repository, mapper and pure
function ships with tests in the same style.

## Dependency policy

Adding a package needs a one-line justification in the PR/summary and an entry
in `pubspec.yaml` with a caret constraint. Prefer the platform or a 60-line
helper over a dependency. Packages the prompts do expect you to add are named
explicitly in each prompt — do not substitute alternatives silently.

## Definition of done (every prompt)

- [ ] `flutter analyze` clean (no new warnings, no `// ignore:` without a reason).
- [ ] `flutter test` green, including the new tests.
- [ ] Every new screen has its empty, loading and error state, in **both**
      themes, and is reachable from a real entry point (not only by route name).
- [ ] Every new async action is cancellable or at least shows progress, and
      surfaces failure through `AppToast.failure` / `InlineErrorBanner` with an
      `AppFailure` message a parent can act on.
- [ ] Offline behaviour is stated and handled — not left to a spinner.
- [ ] No secret, API key, token or notification body is ever `debugPrint`ed,
      sent to Crashlytics, or logged to Analytics.
- [ ] `README.md` updated: new structure rows, new "Not yet wired" entries
      removed or added.
- [ ] Any Firestore shape change ships with matching `firestore.rules`,
      `firestore.indexes.json` and a note on deploying them.

## How to work

Read before you write. Where a prompt says "extend X", open X first and follow
its existing shape. Where a prompt leaves a choice open, pick the option that
adds the least new surface area, and say in your summary which you picked and
why. If a requirement in a prompt contradicts something in the codebase, stop
and say so rather than silently reinterpreting it.
