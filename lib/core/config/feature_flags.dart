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

/// Compile-time kill switch for the whole AI layer (prompt `02`).
///
/// Off, every AI entry point — the More → AI group, "Generate practice",
/// "Scan paper", "Scan report card", the focus plan — is not built at all,
/// and the app must still compile and pass its tests. On, the parent still
/// has to opt in at runtime (`PrefsService.aiEnabled`, default off) and
/// accept the consent screen before anything leaves the device.
const bool kAiEnabled = true;

/// Bumped whenever the consent copy changes materially. A parent who accepted
/// an older version is asked again.
const int kAiConsentVersion = 1;
