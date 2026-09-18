import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../performance/insight_widgets.dart';

/// Add / edit a report card: exam label and date, an optional link to the
/// exam record, then one row per subject with marks, max, grade, absent and
/// remarks. The overall percent updates live in the footer.
class AddResultPage extends StatefulWidget {
  const AddResultPage({super.key, this.existing});

  final ExamResult? existing;

  @override
  State<AddResultPage> createState() => _AddResultPageState();
}

class _AddResultPageState extends State<AddResultPage> {
  /// Common exam names, offered as one-tap chips. They only seed the label —
  /// the label stays free text because schools name things their own way.
  static const _examTypes = [
    'Unit Test 1',
    'Unit Test 2',
    'Term 1',
    'Half Yearly',
    'Term 2',
    'Annual',
  ];

  late final TextEditingController _label = TextEditingController(
    text: widget.existing?.examLabel ?? '',
  );
  late final TextEditingController _sameMax = TextEditingController();
  late final TextEditingController _attendance = TextEditingController(
    text: _fmt(widget.existing?.attendancePercent),
  );
  late final TextEditingController _teacherRemarks = TextEditingController(
    text: widget.existing?.teacherRemarks ?? '',
  );

  late DateTime _date =
      widget.existing?.date ?? DateUtils.dateOnly(DateTime.now());
  late String? _examRecordId = widget.existing?.examRecordId;
  final List<_ScoreDraft> _rows = [];
  bool _seeded = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final existing = widget.existing;
    if (existing != null) {
      for (final score in existing.scores) {
        _rows.add(_ScoreDraft.from(score, onChanged: _refresh));
      }
    } else {
      // A report card usually lists every subject, so every subject starts
      // with a row; the parent deletes the odd one out.
      for (final subject in AppScope.of(context).subjects) {
        _rows.add(_ScoreDraft(subject.name, onChanged: _refresh));
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _sameMax.dispose();
    _attendance.dispose();
    _teacherRemarks.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  static String _fmt(double? v) {
    if (v == null) return '';
    return v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  }

  /// The card as it stands. Numbers that do not parse are simply absent, so
  /// the live percent never throws on a half-typed "7".
  ExamResult _draft() => ExamResult(
    id: widget.existing?.id ?? '',
    childId: widget.existing?.childId ?? '',
    academicYearId: widget.existing?.academicYearId ?? '',
    examLabel: _label.text.trim(),
    date: _date,
    examRecordId: _examRecordId,
    scores: [for (final row in _rows) row.toScore()],
    attendancePercent: double.tryParse(_attendance.text.trim()),
    teacherRemarks: _teacherRemarks.text.trim(),
    source: widget.existing?.source ?? ResultSource.manual,
    extractionConfidence: widget.existing?.extractionConfidence ?? 1,
    needsReview: false,
    gradeScaleId: widget.existing?.gradeScaleId ?? AppScope.read(context).gradeScale.id,
    createdAt: widget.existing?.createdAt,
  );

  bool get _canSave =>
      !_saving && _label.text.trim().isNotEmpty && _rows.isNotEmpty;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickExamRecord() async {
    final state = AppScope.read(context);
    final exams = state.recordsByDateDesc.where((r) => r.isExam).toList();
    if (exams.isEmpty) {
      AppToast.show(
        context,
        title: 'No exam records yet',
        description: 'Add an exam from the + sheet to link it here.',
      );
      return;
    }
    const none = 'Not linked';
    String labelFor(DiaryRecord r) =>
        '${r.examType} · ${r.subject} · ${AppDate.short(r.date)}';
    final current = exams.where((r) => r.id == _examRecordId).firstOrNull;
    final choice = await pickOption(
      context,
      title: 'Link an exam',
      options: [none, for (final r in exams) labelFor(r)],
      current: current == null ? none : labelFor(current),
    );
    if (choice == null || !mounted) return;
    final picked = exams.where((r) => labelFor(r) == choice).firstOrNull;
    setState(() {
      _examRecordId = picked?.id;
      // A linked exam usually *is* the label and the date.
      if (picked != null && _label.text.trim().isEmpty) {
        _label.text = picked.examType;
      }
    });
  }

  void _applySameMax() {
    final value = _sameMax.text.trim();
    if (double.tryParse(value) == null) return;
    setState(() {
      for (final row in _rows) {
        row.max.text = value;
      }
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _addSubjectRow() async {
    final controller = TextEditingController();
    final name = await AppSheet.show<String>(
      context,
      (sheetContext) => AppSheet(
        title: 'Add a subject row',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Subject',
              controller: controller,
              hintText: 'Social Science',
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            AppFilledButton(
              label: 'Add row',
              height: 50,
              elevated: false,
              onPressed: () =>
                  Navigator.of(sheetContext).pop(controller.text.trim()),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    if (_rows.any((r) => r.subject.toLowerCase() == name.toLowerCase())) {
      AppToast.show(
        context,
        title: 'Already listed',
        description: '$name is already on this card.',
      );
      return;
    }
    setState(() => _rows.add(_ScoreDraft(name, onChanged: _refresh)));
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final state = AppScope.read(context);
    var draft = _draft();

    // §G: the same card entered twice is the commonest data-entry slip. Ask
    // before it happens rather than showing two "Term 1" rows forever.
    if (!_isEditing) {
      final twins = state.duplicatesOf(draft);
      if (twins.isNotEmpty) {
        final choice = await _askDuplicate(twins.first);
        if (choice == null || !mounted) return;
        if (choice == _DuplicateChoice.replace) {
          draft = draft.copyWith(
            id: twins.first.id,
            createdAt: twins.first.createdAt,
          );
        }
      }
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await state.saveResult(draft);
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: _isEditing ? 'Marks updated' : 'Marks saved',
        description:
            '${saved.examLabel} · ${percentLabel(saved.overallPercent)} overall.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save marks");
    }
  }

  Future<_DuplicateChoice?> _askDuplicate(ExamResult twin) {
    final k = context.t;
    return showDialog<_DuplicateChoice>(
      context: context,
      barrierColor: const Color(0x6B1F1B16),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(28),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Already saved?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '"${twin.examLabel}" dated ${AppDate.full(twin.date)} is '
                'already in the diary. Replace it with this one, or keep both?',
                style: TextStyle(fontSize: 14, height: 1.55, color: k.tx3),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AppOutlinedButton(
                      label: 'Keep both',
                      height: 50,
                      borderRadius: 15,
                      onPressed: () =>
                          Navigator.of(context).pop(_DuplicateChoice.keepBoth),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppFilledButton(
                      label: 'Replace',
                      height: 50,
                      elevated: false,
                      onPressed: () =>
                          Navigator.of(context).pop(_DuplicateChoice.replace),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final draft = _draft();
    final overall = draft.overallPercent;
    final linked = _examRecordId == null
        ? null
        : state.recordById(_examRecordId!);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: _isEditing ? 'Edit Marks' : 'Add Marks',
                actions: [
                  if (!_isEditing && state.aiAvailable)
                    AppIconButton(
                      tooltip: 'Scan report card',
                      background: k.priC,
                      hoverBackground: k.priCH,
                      onTap: () => Navigator.of(context)
                          .pushReplacementNamed(Routes.scanResult),
                      child: StrokeIcon(AppIcons.camera, size: 19, color: k.priInk),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  FieldLabel('Exam type', emphasis: FieldEmphasis.primary),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in _examTypes)
                        AppChip(
                          label: type,
                          selected: _label.text.trim() == type,
                          onTap: () => setState(() => _label.text = type),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Exam name',
                    controller: _label,
                    hintText: 'Unit Test 1, Term 1, Half Yearly…',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  PickerField(
                    label: 'Date',
                    value: AppDate.full(_date),
                    trailing: PickerTrailing.calendar,
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 18),
                  PickerField(
                    label: 'Linked exam (optional)',
                    value: linked == null
                        ? 'Not linked'
                        : '${linked.examType} · ${linked.subject}',
                    isPlaceholder: linked == null,
                    onTap: _pickExamRecord,
                  ),
                  const SizedBox(height: 18),
                  const HairLine(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Subjects',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Grades use ${state.gradeScale.label}',
                        style: TextStyle(fontSize: 12, color: k.tx4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // A report card almost always has one maximum for every
                  // subject; typing it five times is the kind of chore that
                  // stops a parent entering marks at all.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Same max marks for all',
                          controller: _sameMax,
                          hintText: '100',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppTonalButton(
                        label: 'Apply',
                        height: 56,
                        fontSize: 14,
                        borderRadius: 14,
                        background: k.priC,
                        hoverBackground: k.priCH,
                        foreground: k.priInk,
                        onPressed: _applySameMax,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < _rows.length; i++) ...[
                    _ScoreRowCard(
                      draft: _rows[i],
                      known: state.subjectNames.contains(_rows[i].subject),
                      onRemove: () => setState(() {
                        _rows.removeAt(i).dispose();
                      }),
                    ),
                    const SizedBox(height: 10),
                  ],
                  AppOutlinedButton(
                    label: 'Add another subject',
                    height: 48,
                    icon: const StrokeIcon(
                      AppIcons.plus,
                      size: 18,
                      strokeWidth: 2.2,
                    ),
                    onPressed: _addSubjectRow,
                  ),
                  const SizedBox(height: 18),
                  const HairLine(),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Attendance % (optional)',
                    controller: _attendance,
                    hintText: '96',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: "Teacher's remarks (optional)",
                    controller: _teacherRemarks,
                    hintText: 'Anything written on the card',
                    maxLines: 3,
                    minHeight: 66,
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'OVERALL',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .6,
                          color: k.tx4,
                        ),
                      ),
                      Text(
                        percentLabel(overall),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.1,
                          color: overall == null ? k.tx4 : k.priInk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppFilledButton(
                      label: _saving
                          ? 'Saving…'
                          : (_isEditing ? 'Save Changes' : 'Save Marks'),
                      onPressed: _canSave ? _save : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DuplicateChoice { replace, keepBoth }

/// Controllers for one subject row. Kept outside the widget so the list can
/// be reordered or trimmed without losing typed text.
class _ScoreDraft {
  _ScoreDraft(this.subject, {required VoidCallback onChanged})
    : marks = TextEditingController(),
      max = TextEditingController(),
      grade = TextEditingController(),
      remarks = TextEditingController() {
    for (final c in [marks, max, grade, remarks]) {
      c.addListener(onChanged);
    }
  }

  factory _ScoreDraft.from(SubjectScore s, {required VoidCallback onChanged}) {
    final d = _ScoreDraft(s.subject, onChanged: onChanged)
      ..absent = s.absent
      ..classRank = s.classRank;
    d.marks.text = _AddResultPageState._fmt(s.marks);
    d.max.text = _AddResultPageState._fmt(s.maxMarks);
    d.grade.text = s.grade ?? '';
    d.remarks.text = s.remarks;
    return d;
  }

  final String subject;
  final TextEditingController marks, max, grade, remarks;
  bool absent = false;
  int? classRank;

  SubjectScore toScore() => SubjectScore(
    subject: subject,
    marks: double.tryParse(marks.text.trim()),
    maxMarks: double.tryParse(max.text.trim()),
    grade: grade.text.trim().isEmpty ? null : grade.text.trim(),
    classRank: classRank,
    remarks: remarks.text.trim(),
    absent: absent,
  );

  void dispose() {
    marks.dispose();
    max.dispose();
    grade.dispose();
    remarks.dispose();
  }
}

class _ScoreRowCard extends StatelessWidget {
  const _ScoreRowCard({
    required this.draft,
    required this.known,
    required this.onRemove,
  });

  final _ScoreDraft draft;

  /// False for a subject the child does not have — shown neutral (§G).
  final bool known;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(draft.subject);
    final score = draft.toScore();
    final percent = score.percent;

    return AppCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Dot(color: subject.hue.dot(k), size: 9),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        draft.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!known) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        label: 'New',
                        background: k.surf2,
                        foreground: k.tx3,
                      ),
                    ],
                  ],
                ),
              ),
              if (percent != null && !draft.absent)
                Text(
                  '${percent.round()}%${score.isDerivedPercent ? ' ≈' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: k.priInk,
                  ),
                ),
              const SizedBox(width: 4),
              AppIconButton(
                size: 32,
                borderRadius: 10,
                hoverBackground: k.errC,
                tooltip: 'Remove row',
                onTap: onRemove,
                child: StrokeIcon(AppIcons.close, size: 16, color: k.tx4),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Marks',
                  controller: draft.marks,
                  hintText: '72',
                  minHeight: 48,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppTextField(
                  label: 'Out of',
                  controller: draft.max,
                  hintText: '100',
                  minHeight: 48,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppTextField(
                  label: 'Grade',
                  controller: draft.grade,
                  hintText: 'A1',
                  minHeight: 48,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Remarks',
                  controller: draft.remarks,
                  hintText: 'Revise chapter 4',
                  minHeight: 48,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  FieldLabel('Absent'),
                  const SizedBox(height: 8),
                  AppSwitch(
                    value: draft.absent,
                    width: 48,
                    height: 28,
                    activeColor: k.warn,
                    onChanged: (v) {
                      draft.absent = v;
                      // The row's own listener only watches text; flip the
                      // page so the live percent drops this row.
                      context.findAncestorStateOfType<_AddResultPageState>()
                          ?._refresh();
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
