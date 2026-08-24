# Parent Academic Diary

Flutter implementation of the `Parent Academic Diary.dc.html` prototype from the
[Claude Design project](https://claude.ai/design/p/cee58f26-2f63-4f15-a078-d06c3adaee56),
built against the accompanying *Academic Diary Style Guide* (Material 3 tokens,
Android, 412dp).

Parents keep a child's worksheets and classwork in one place: capture pages with
the camera, accept an image shared in from WhatsApp, and browse everything on an
academic timeline grouped by day and by subject.

## Exam and marks UI is excluded

The prototype declares a `showExamMarks` prop (default `false`) and gates every
exam- and marks-related surface behind it. This build mirrors that switch as
`kShowExamMarks` in `lib/core/config/feature_flags.dart`, so the excluded UI is
one constant away rather than deleted. With the flag off:

| Excluded | Where the design puts it |
| --- | --- |
| Performance tab | bottom navigation, between Timeline and More |
| Add exam / Add marks | home quick actions, the Add sheet |
| Exam detail, Marks history, Exams list | pushed from the timeline and lists |
| "Latest marks" block | home dashboard |
| Exam / Marks timeline entries | academic timeline |
| Exams / Marks subject tabs and the trend chart | subject detail |
| Exam / Marks filter chips | timeline filter sheet |
| Exams group | search results |

Three follow-on calls were made where the design does not gate something that
depends on marks. Each is commented at the site:

- **Onboarding slide 3** ("Track Academic Progress") follows the same flag — its
  entire content is a marks trend chart.
- **Onboarding slide 1** copy drops "and exam papers", and its fourth tile reads
  "Homework" instead of "Exam paper".
- **Subject detail** is reached from the Worksheets / Classwork subject group
  headers. The design's only entry point is the Performance tab, which is gone;
  its header shows a record count where the design shows an average mark.

## Structure

```
lib/
  app/            MaterialApp, theme wiring, root route table
  core/
    config/       kShowExamMarks
    theme/        design tokens (light + dark), ThemeData, subject hues
    widgets/      buttons, chips, fields, cards, sheets, toast, states,
                  ImageSlot, and a small SVG path renderer for the icon set
    format.dart   date and count formatting
  data/           models, in-memory AppState, sample content
  features/       one directory per screen family
  shell/          three-tab frame (Home / Timeline / More) and the Add sheet
```

**State** is one `ChangeNotifier` (`AppState`) handed down by an
`InheritedNotifier`. No packages beyond the SDK.

**Data** lives in `lib/data/sample_data.dart`, transcribed from the prototype's
`renderVals()`. There is no backend yet: saving a record updates the in-memory
list, exactly as the prototype does. Swap that file for a repository and nothing
above it changes.

**Icons** are the design's own stroked 24×24 SVG paths, rendered by
`core/widgets/stroke_icon.dart` rather than approximated with Material glyphs.

**Theming** — both palettes come straight from the prototype's `:root` and
`[data-theme="dark"]` blocks, exposed as an `AppTokens` `ThemeExtension`. Read
them with `context.t`. Toggle in More → Theme.

**Fonts** — Figtree 400–800 is bundled under `assets/fonts/`, so no network
fetch at runtime.

## Running

```sh
flutter pub get
flutter run
```

## Tests

```sh
flutter test
```

`test/app_smoke_test.dart` walks splash → onboarding → login → child setup →
home, saves a worksheet, opens detail screens, switches to dark, and asserts
that no exam or marks surface is reachable.

To refresh the reference screenshots in `tool/screenshots/`:

```sh
flutter test tool/capture_screens_test.dart --update-goldens
```

That helper lives outside `test/` on purpose — the images are for eyeballing
layout, not assertions.

## Not yet wired

The UI is complete; these hand off to platform work:

- Google sign-in (the button advances to child setup)
- real camera / gallery / file pickers (the picker screen returns a count)
- attachment storage and rendering (`ImageSlot` takes an `ImageProvider`)
- persistence, sync, and the share-sheet intent that opens *Create Academic
  Record*
