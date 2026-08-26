import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../core/services/image_service.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/repositories/attachment_repository.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';

/// Add / edit classwork: subject, title, date, notes and a photo drop zone.
class AddClassworkPage extends StatefulWidget {
  const AddClassworkPage({super.key, this.existing});

  final DiaryRecord? existing;

  @override
  State<AddClassworkPage> createState() => _AddClassworkPageState();
}

class _AddClassworkPageState extends State<AddClassworkPage> {
  static final List<String> _chapterOptions = [
    for (var i = 1; i <= 50; i++) 'Chapter $i',
  ];

  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  String? _subject;
  late String? _chapter = (widget.existing?.chapter ?? '').isEmpty
      ? ((widget.existing?.title ?? '').isEmpty ? null : widget.existing!.title)
      : widget.existing!.chapter;

  /// §37: today by default.
  late DateTime _date =
      widget.existing?.date ?? DateUtils.dateOnly(DateTime.now());
  late final List<Attachment> _photos =
      List.of(widget.existing?.attachments ?? const []);

  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _canSave =>
      !_saving && _chapter != null && _subject != null;

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
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickChapter() async {
    final choice = await pickOption(
      context,
      title: 'Chapter',
      options: _chapterOptions,
      current: _chapter ?? '',
    );
    if (choice != null) setState(() => _chapter = choice);
  }

  Future<void> _addPhotos([AttachmentSource source = AttachmentSource.camera]) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) => PickerPage(initialSource: source),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      for (final file in picked) {
        _photos.add(
          AttachmentRepository.stage(
            file,
            caption: 'Photo ${_photos.length + 1}',
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
    final chapter = _chapter!;

    final record = DiaryRecord(
      id: widget.existing?.id ?? '',
      childId: widget.existing?.childId ?? '',
      academicYearId: widget.existing?.academicYearId ?? state.activeYear,
      type: RecordType.classwork,
      subject: subject,
      title: chapter,
      date: _date,
      chapter: chapter,
      notes: _notes.text.trim(),
      attachments: _photos,
      createdAt: widget.existing?.createdAt,
    );

    try {
      await state.saveRecord(record);
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: _isEditing ? 'Classwork updated' : 'Classwork saved',
        description: '${AppFormat.photoCount(_photos.length)} added to '
            '$subject classwork.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save classwork");
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
                title: _isEditing ? 'Edit Classwork' : 'Add Classwork',
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
                  PickerField(
                    label: 'Chapter',
                    value: _chapter ?? 'Select a chapter',
                    isPlaceholder: _chapter == null,
                    onTap: _pickChapter,
                  ),
                  const SizedBox(height: 18),
                  PickerField(
                    label: 'Date',
                    value: AppDate.full(_date),
                    trailing: PickerTrailing.calendar,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Notes',
                    controller: _notes,
                    hintText: 'Optional — copied from board',
                    maxLines: 3,
                    minHeight: 66,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Classwork',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppFormat.photoCount(_photos.length),
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
                    emphasizeFirst: true,
                    onPick: _addPhotos,
                  ),
                  if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (var i = 0; i < _photos.length; i++)
                          Stack(
                            fit: StackFit.expand,
                            children: [
                              attachmentThumb(
                                context,
                                _photos[i],
                                radius: 14,
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Material(
                                  color: k.bg.withValues(alpha: .9),
                                  shape: const CircleBorder(),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _photos.removeAt(i)),
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
                    : (_isEditing ? 'Save Changes' : 'Save Classwork'),
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


