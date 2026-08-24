/// Mirrors the `showExamMarks` prop declared by the design
/// (`data-props` on `Parent Academic Diary.dc.html`, default `false`).
///
/// The design already gates every exam- and marks-related surface behind this
/// flag: the Performance tab, exam/marks quick actions, the "Latest marks"
/// block, exam/marks timeline entries, the Exams/Marks subject tabs, and the
/// exam/marks filter chips. Keeping the same switch here means the excluded UI
/// is one constant away from being turned on, rather than deleted.
const bool kShowExamMarks = false;
