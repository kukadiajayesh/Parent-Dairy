/// Mirrors the `showExamMarks` prop declared by the design
/// (`data-props` on `Parent Academic Diary.dc.html`, default `false`).
///
/// The design gates every exam- and marks-related surface behind this flag:
/// the Performance tab, exam/marks quick actions, the "Latest marks" block,
/// exam/marks timeline entries, the Exams/Marks subject tabs, and the
/// exam/marks filter chips. The switch stays in place even now that those
/// surfaces are built — it is how the build stays shippable if a marks screen
/// ever has to be pulled mid-release.
const bool kShowExamMarks = true;

/// Master switch for every AI entry point (the Gemini prompt, `02`). Off until
/// that layer lands; the Performance tab's "Generate practice" action is the
/// only caller so far and hides behind it.
const bool kAiEnabled = false;
