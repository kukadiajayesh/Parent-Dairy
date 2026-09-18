# 04 — Deep UI review and performance

> Assumes `00-shared-context.md`. Run **last**, so the audit covers the screens
> prompts `01`–`03` add.

## Goal

Two passes over the whole app: one for how it looks and reads, one for how it
runs. Both end in measured before/after numbers and a fix list, not adjectives.

Work in this order: **measure → report → fix the top items → re-measure.** Do
not start editing widgets before the report exists.

---

## Part 1 — Performance

### Known suspects (verify each before changing it)

These came out of a read of the code and are where to look first. Confirm with a
profile trace; do not "fix" something that is not slow.

1. **`SliverList.list` builds every child eagerly.** `timeline_page.dart:82` and
   `home_page.dart:108` both use it. With a year of records the timeline builds
   hundreds of widgets to draw ten. Convert to `SliverList.builder` /
   `SliverChildBuilderDelegate`, and use `SliverFixedExtentList` or
   `prototypeItem` wherever rows are a fixed height.
2. **Full-resolution images decoded into thumbnails.** `attachmentImage()` in
   `attachment_image.dart` returns a bare `FileImage` / `NetworkImage`. Worksheet
   photos are stored at up to 2000px on the long edge and are drawn into ~72dp
   slots — that is roughly 16MB of decoded ARGB per image held in the image
   cache. Wrap in `ResizeImage` with a `cacheWidth` derived from the slot's
   logical size × `devicePixelRatio`. Expect the largest single win here.
3. **`AppScope.of(context)` rebuilds every dependent on every notify.**
   `AppState` notifies on connectivity ticks, upload progress, filter changes and
   every Firestore snapshot; today that rebuilds Home, Timeline, More and every
   card inside them. Add narrowed access — an `AppSelector<T>` widget (or
   `InheritedModel` aspects) so a card that only reads `records` does not rebuild
   when the upload queue ticks. Keep `AppScope.of` working; migrate the hot
   screens only.
4. **`groupBySubject` runs in `build()`.** It is O(subjects × records) and is
   called from the timeline and both list screens on every rebuild. Memoise
   against `(records identity, _listSubject)` inside `AppState`.
5. **`StrokeIcon` — already handled, do not "fix" it.** `SvgPath.parse`
   memoises every parsed `Path` in a static map and `shouldRepaint` already
   compares icon, colour and stroke width. Left here so the audit does not
   rediscover it as a problem. If icons still show in a trace, the cost is the
   `CustomPaint` count, not the parsing — batch small icon rows behind a single
   `RepaintBoundary` instead.
6. **No `RepaintBoundary` around thumbnails and skeleton shimmer.** The
   `Skeletons` animation repaints its whole subtree; attachment grids repaint on
   any parent rebuild.
7. **`File.existsSync()` in `build()`** (`attachment_image.dart:30`) — a stat
   per image per frame. Cache the result per path for the session.
8. **`RecordRepository.pageSize = 400`** holds 400 documents in memory for one
   screen. Add pagination to the timeline (load 60, extend on scroll) and keep
   400 only for search.
9. **`PdfThumbnailService` caches in memory only, and unboundedly.** Renders
   are already memoised by attachment id and serialised behind a `Lock`, which
   is right — but the map never evicts, and every thumbnail is re-rendered after
   a cold start. Add an LRU bound (say 60 entries) and persist the rasters under
   the app's cache directory keyed by attachment id.
10. **Startup is serial.** `main.dart` awaits `PrefsService.init()`, then
    `Firebase.initializeApp`, then `Telemetry.init()` before `runApp`, and
    `app.dart:52` then awaits `NotificationService.init()` — which pulls in
    timezone database loading. Prefs genuinely must precede the first frame (the
    theme and remembered child come from it); the rest does not. Push the
    remainder behind the first frame and run the independent pieces
    concurrently with `Future.wait`.

### How to measure

```sh
flutter run --profile --trace-startup            # startup timeline
flutter run --profile                            # + DevTools > Performance
flutter test --enable-vmservice                  # unaffected
flutter build apk --release --analyze-size       # APK size
```

Record, before and after, on a real mid-range Android device (not an emulator):

| Metric | Target |
| --- | --- |
| Time to first frame (`--trace-startup`) | < 1.5s cold |
| Timeline scroll, 200 records: p50 / p95 build+raster | < 6ms / < 16ms |
| Dropped frames scrolling the timeline end to end | 0 janky frames |
| Peak image cache during a timeline scroll | < 60MB |
| Memory after 3 min of normal use | no upward drift |
| Release APK (arm64 split) | report it; note anything the AI/PDF deps add |

Add `--split-per-abi`, confirm R8 and `shrinkResources` are on for release, and
check that the debug signing config TODO in `android/app/build.gradle.kts` is
still flagged.

### Guardrail test

Add `test/performance_guard_test.dart`: build the timeline with 500 fake records
and assert the number of `RecordCard` widgets actually built stays under ~30.
It is a cheap regression net against someone reintroducing `SliverList.list`.

---

## Part 2 — UI review

Go screen by screen — Splash, Onboarding, Login, Child setup, Home, Timeline,
Worksheets, Classwork, Subject, Search, Viewer, Picker, Share flow, More and
every settings page, plus everything prompts `01`–`03` added. For each, check:

### Consistency

- Spacing is on the scale the design already uses (4/8/10/12/16/20/24); flag
  one-off values.
- Every colour comes from `context.t`; no literal hex outside `app_tokens.dart`.
- Radii, border weights, shadows and card padding match `AppCard`.
- Icons are `StrokeIcon`; flag any `Icons.` that crept in.
- Typography: the set of size/weight pairs in use should be small. List them;
  if there are more than ~8, propose a `TextStyle` set in the theme.
- Empty, loading and error states exist and are consistent with
  `EmptyStateView` / `Skeletons` / `ErrorStateView`.

### Dark mode

Open every screen in both themes. Look for: text on tinted chips falling below
contrast, skeletons invisible, dashed borders vanishing, elevation reading as a
grey box, subject hues losing distinction.

### Accessibility

- Tap targets ≥ 48×48dp — icon-only buttons are the usual offenders.
- Contrast ≥ 4.5:1 for body text, 3:1 for large text and icons, in both themes.
  Report every failure with the token pair and a suggested fix.
- `Semantics` labels on every icon-only control, image thumbnail
  ("Worksheet page 1, Mathematics") and status pill.
- `MediaQuery.textScaler` at 1.3 and 2.0: no clipped text, no overflow. Test at
  411.4dp, per the existing convention.
- Focus order and keyboard/switch traversal on forms.
- Respect `MediaQuery.disableAnimations`.

### Interaction

- Every destructive action is reversible or confirmed (the app already does this
  well for deletes — keep it consistent in the new screens).
- Loading states are specific ("Uploading page 2 of 5", "Reading 4 pages"), not
  a bare spinner.
- Long-running AI and upload work can be backgrounded without losing progress.
- Haptics on primary confirmations only; not on every tap.
- Back/`PopScope` on forms with unsaved changes.

### Copy

Plain, parent-facing, no jargon: no "sync failed", "quota exceeded",
"null", "exception". Every error says what happened and what to do. The AI
screens in particular must never over-promise — "AI-generated, check it" is a
fixed part of the voice.

---

## Deliverables

1. `docs/audit/performance.md` — the before/after table, each suspect confirmed
   or dismissed with evidence (a trace screenshot or a number), and what was
   changed.
2. `docs/audit/ui-review.md` — screen-by-screen findings, each tagged
   **blocker / should-fix / nice-to-have**, with the file and line.
3. The blocker and should-fix items implemented, in separate, reviewable
   commits — one concern per commit, not a single "polish" commit.
4. `flutter analyze` clean, `flutter test` green, and the golden screenshots in
   `tool/screenshots/` refreshed:

```sh
flutter test tool/capture_screens_test.dart --update-goldens
```

5. A short "known remaining" list at the end of the UI review — what you found,
   judged, and deliberately did not change.
