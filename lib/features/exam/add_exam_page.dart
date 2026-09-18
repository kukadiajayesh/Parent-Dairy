import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/repositories/attachment_repository.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';

/// Add / edit an exam: subject, exam type, timetable (single image) and
/// previous exam papers (multiple images) — both attachment slots are
/// image-only, since a timetable or a paper is always photographed or
/// screenshotted, never a PDF scan.
class AddExamPage extends StatefulWidget {
  const AddExamPage({super.key, this.existing});

  final DiaryRecord? existing;

  @override
  State<AddExamPage> createState() => _AddExamPageState();
}

class _AddExamPageState extends State<AddExamPage> {
  late final TextEditingController _examType =
      TextEditingController(text: widget.existing?.examType ?? '');

  String? _subject;
  late DateTime _date =
      widget.existing?.date ?? DateUtils.dateOnly(DateTime.now());
  late Attachment? _timetable = widget.existing?.examTimetable;
  late final List<Attachment> _previousPapers =
      List.of(widget.existing?.attachments ?? const []);

  bool _saving = false;

  /// A draft handed in with no id (a converted school notice) is still a
  /// new exam, not an edit.
  bool get _isEditing => widget.existing?.id.isNotEmpty == true;
  bool get _canSave =>
      !_saving &&
      _subject != null &&
      _examType.text.trim().isNotEmpty &&
      _timetable != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subject != null) return;
    final state = AppScope.of(context);
    final suggested = widget.existing?.subject ?? state.suggestedSubject;
    if (suggested.isNotEmpty) _subject = suggested;
  }

  @override
  void dispose() {
    _examType.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTimetable(AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) => PickerPage(
          initialSource: source,
          allowMultiple: false,
          imagesOnly: true,
        ),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      _timetable = AttachmentRepository.stage(
        picked.first,
        caption: ImageService.humanSize(picked.first.bytes),
      );
    });
  }

  Future<void> _pickPreviousPapers(AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) =>
            PickerPage(initialSource: source, imagesOnly: true),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      for (final file in picked) {
        _previousPapers.add(
          AttachmentRepository.stage(
            file,
            caption: 'Page ${_previousPapers.length + 1}',
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final subject = _subject!;
    final examType = _examType.text.trim();

    final record = DiaryRecord(
      id: widget.existing?.id ?? '',
      childId: widget.existing?.childId ?? '',
      academicYearId: widget.existing?.academicYearId ?? state.activeYear,
      type: RecordType.exam,
      subject: subject,
      title: examType,
      date: _date,
      examType: examType,
      examTimetable: _timetable,
      attachments: _previousPapers,
      notes: widget.existing?.notes ?? '',
      origin: widget.existing?.origin ?? RecordOrigin.manual,
      createdAt: widget.existing?.createdAt,
    );

    try {
      final saved = await state.saveRecord(record);
      if (!mounted) return;
      // Handed back so a caller that drafted this (notice → exam) can link
      // the record it became.
      navigator.pop(saved);
      AppToast.showOn(
        messenger,
        context,
        title: _isEditing ? 'Exam updated' : 'Exam saved',
        description: '$subject exam added to your timeline.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save exam");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: _isEditing ? 'Edit Exam' : 'Add Exam',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  FieldLabel('Subject', emphasis: FieldEmphasis.primary),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final subject in state.subjects)
                        SubjectChip(
                          name: subject.name,
                          hue: subject.hue,
                          selected: _subject == subject.name,
                          onTap: () => setState(() => _subject = subject.name),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Exam type',
                    controller: _examType,
                    hintText: 'Unit Test 1, Mid-term, Final…',
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
                  const HairLine(),
                  const SizedBox(height: 18),
                  const Text(
                    'Exam timetable',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (_timetable != null)
                    AppCard(
                      radius: 14,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          attachmentThumb(
                            context,
                            _timetable,
                            radius: 12,
                            width: 52,
                            height: 52,
                            showCaption: false,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _timetable!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          AppIconButton(
                            size: 34,
                            borderRadius: 10,
                            hoverBackground: k.errC,
                            onTap: () => setState(() => _timetable = null),
                            tooltip: 'Remove',
                            child:
                                StrokeIcon(AppIcons.close, size: 17, color: k.err),
                          ),
                        ],
                      ),
                    )
                  else
                    AttachmentSourceRow(
                      emphasizeFirst: true,
                      showFiles: false,
                      onPick: _pickTimetable,
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Text(
                        'Previous exam papers',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Optional',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: k.tx4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AttachmentSourceRow(
                    showFiles: false,
                    onPick: _pickPreviousPapers,
                  ),
                  if (_previousPapers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (var i = 0; i < _previousPapers.length; i++)
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              attachmentThumb(
                                context,
                                _previousPapers[i],
                                radius: 14,
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: PressDip(
                                  child: Material(
                                    color: k.bg.withValues(alpha: .9),
                                    shape: const CircleBorder(),
                                    clipBehavior: Clip.antiAlias,
                                    child: AppInkWell(
                                      onTap: () => setState(
                                        () => _previousPapers.removeAt(i),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: StrokeIcon(
                                          AppIcons.close,
                                          size: 13,
                                          color: k.err,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: _saving
                    ? 'Saving…'
                    : (_isEditing ? 'Save Changes' : 'Save Exam'),
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
