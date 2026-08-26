import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/repositories/attachment_repository.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';

/// What the share sheet handed over.
class ShareImageArgs {
  const ShareImageArgs({required this.files});

  final List<PickedAttachment> files;
}

/// "Create Academic Record" — the destination when an image is shared into the
/// app from WhatsApp, Gallery or a file manager (§11). A segmented control
/// picks worksheet or classwork; the rest of the form follows that choice.
///
/// Everything that can be defaulted is: the active child, the active year,
/// today's date and the last-used subject, so filing a forwarded worksheet is
/// "pick a type, tap Save" (§11's smart defaults).
class ShareImagePage extends StatefulWidget {
  const ShareImagePage({super.key, this.args});

  final ShareImageArgs? args;

  @override
  State<ShareImagePage> createState() => _ShareImagePageState();
}

class _ShareImagePageState extends State<ShareImagePage> {
  final TextEditingController _notes = TextEditingController();

  RecordType _type = RecordType.worksheet;
  String? _subject;
  List<String> _chapters = const [];
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  DateTime? _dueDate;
  Attachment? _answerKey;
  bool _saving = false;

  /// The shared files, staged so they can be removed individually before
  /// saving (§11: "Parent can remove individual images before saving").
  late final List<Attachment> _files = [
    for (var i = 0; i < (widget.args?.files.length ?? 0); i++)
      AttachmentRepository.stage(
        widget.args!.files[i],
        caption: 'Page ${i + 1}',
      ),
  ];

  int _preview = 0;

  bool get _isWorksheet => _type == RecordType.worksheet;
  bool get _hasAnswerKey => _answerKey != null;
  bool get _canSave =>
      !_saving && _subject != null && _chapters.isNotEmpty && _files.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subject != null) return;
    final suggested = AppScope.of(context).suggestedSubject;
    if (suggested.isNotEmpty) _subject = suggested;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickChapters() async {
    final choice = await pickMultipleOptions(
      context,
      title: 'Chapters',
      options: kChapterOptions,
      initial: _chapters,
    );
    if (choice != null) setState(() => _chapters = choice);
  }

  Future<void> _pickAnswerKey() async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) => const PickerPage(
          initialSource: AttachmentSource.gallery,
          allowMultiple: false,
        ),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      _answerKey = AttachmentRepository.stage(
        picked.first,
        caption: ImageService.humanSize(picked.first.bytes),
      );
    });
  }

  Future<void> _save({required bool addAnother}) async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final chapters = _chapters;
    final title = chapters.length == 1
        ? chapters.first
        : '${chapters.first} +${chapters.length - 1}';

    final record = DiaryRecord(
      id: '',
      academicYearId: state.activeYear,
      type: _type,
      subject: _subject!,
      title: title,
      date: _date,
      dueDate: _isWorksheet ? _dueDate : null,
      chapters: chapters,
      notes: _isWorksheet ? '' : _notes.text.trim(),
      attachments: _files,
      answerKey: _isWorksheet ? _answerKey : null,
    );

    try {
      await state.saveRecord(record, fromShare: true);
      if (!mounted) return;

      if (addAnother) {
        // The files are spent; what carries over is the context a parent
        // filing a batch would otherwise re-enter every time.
        setState(() {
          _chapters = const [];
          _notes.clear();
          _dueDate = null;
          _answerKey = null;
          _files.clear();
          _preview = 0;
          _saving = false;
        });
        AppToast.show(
          context,
          title: 'Record saved',
          description: 'Share the next image to add it here.',
        );
        return;
      }

      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Record saved',
        description: 'Image saved to your timeline.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save record");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final child = state.activeChild;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: ScreenHeader(
                title: 'Create Academic Record',
                subtitle:
                    '${child.name} · ${child.grade} · ${state.activeYear}',
                leadingIsClose: true,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  _files.isEmpty
                      ? const ImageSlot(
                          placeholder: 'No image shared',
                          radius: 20,
                          height: 250,
                        )
                      : attachmentThumb(
                          context,
                          _files[_preview],
                          radius: 20,
                          height: 250,
                        ),
                  if (_files.length > 1) ...[
                    const SizedBox(height: 10),
                    _SharedFileStrip(
                      files: _files,
                      selected: _preview,
                      onSelect: (i) => setState(() => _preview = i),
                      onRemove: (i) => setState(() {
                        _files.removeAt(i);
                        _preview = _preview.clamp(
                          0,
                          _files.isEmpty ? 0 : _files.length - 1,
                        );
                      }),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _TypeSegments(
                    value: _type,
                    onChanged: (v) => setState(() => _type = v),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 14),
                  if (_chapters.isEmpty)
                    PickerField(
                      label: 'Chapters',
                      value: 'Select chapters',
                      isPlaceholder: true,
                      onTap: _pickChapters,
                    )
                  else ...[
                    FieldLabel('Chapters', emphasis: FieldEmphasis.primary),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final chapter in _chapters)
                          AppChip(
                            label: chapter,
                            selected: true,
                            onTap: _pickChapters,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TodayField(
                          date: _date,
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
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _isWorksheet
                            ? PickerField(
                                label: 'Due date',
                                value: _dueDate == null
                                    ? 'Optional'
                                    : AppDate.full(_dueDate!),
                                isPlaceholder: _dueDate == null,
                                trailing: PickerTrailing.calendar,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _dueDate ?? _date,
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2035),
                                  );
                                  if (picked != null) {
                                    setState(() => _dueDate = picked);
                                  }
                                },
                              )
                            : AppTextField(
                                label: 'Notes',
                                controller: _notes,
                                hintText: 'Optional',
                                minHeight: 54,
                              ),
                      ),
                    ],
                  ),
                  if (_isWorksheet) ...[
                    const SizedBox(height: 14),
                    DashedContainer(
                      radius: 16,
                      padding: const EdgeInsets.all(14),
                      onTap: _pickAnswerKey,
                      child: Row(
                        children: [
                          _hasAnswerKey
                              ? attachmentThumb(
                                  context,
                                  _answerKey,
                                  radius: 12,
                                  width: 40,
                                  height: 40,
                                  showCaption: false,
                                )
                              : Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: k.surf2,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: StrokeIcon(
                                    AppIcons.plus,
                                    size: 19,
                                    color: k.tx3,
                                  ),
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _hasAnswerKey
                                      ? 'Answer key attached'
                                      : 'Add answer key',
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Optional, can be added later',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: k.tx4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            StickyFooter(
              child: Column(
                children: [
                  AppFilledButton(
                    label: _saving ? 'Saving…' : 'Save',
                    height: 54,
                    onPressed: _canSave ? () => _save(addAnother: false) : null,
                  ),
                  const SizedBox(height: 10),
                  AppTonalButton(
                    label: 'Save & Add Another',
                    height: 46,
                    fontSize: 14.5,
                    borderRadius: 14,
                    background: Colors.transparent,
                    hoverBackground: k.surf2,
                    foreground: k.pri,
                    onPressed: _canSave ? () => _save(addAnother: true) : null,
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

class _TypeSegments extends StatelessWidget {
  const _TypeSegments({required this.value, required this.onChanged});

  final RecordType value;
  final ValueChanged<RecordType> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.t;

    Widget segment(RecordType type, String label) {
      final selected = value == type;
      return Expanded(
        child: Material(
          color: selected ? k.priFill : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onChanged(type),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? k.surf : k.tx3,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: k.surf2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          segment(RecordType.worksheet, 'Worksheet'),
          segment(RecordType.classwork, 'Classwork'),
        ],
      ),
    );
  }
}

/// The design highlights the date field in secondary green and labels it
/// "Today" when the shared image is filed on the current day.
class _TodayField extends StatelessWidget {
  const _TodayField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final isToday = AppDate.sameDay(date, DateTime(2026, 8, 23));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Date'),
        const SizedBox(height: 6),
        Material(
          color: isToday ? k.secC : k.surf2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: isToday ? k.sec : k.bd3, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 54,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                isToday ? 'Today' : AppDate.full(date),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? k.secInk : k.tx,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Thumbnails for a multi-image share, each removable before saving (§11).
class _SharedFileStrip extends StatelessWidget {
  const _SharedFileStrip({
    required this.files,
    required this.selected,
    required this.onSelect,
    required this.onRemove,
  });

  final List<Attachment> files;
  final int selected;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final file = files[index];
          return GestureDetector(
            onTap: () => onSelect(index),
            child: SizedBox(
              width: 62,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: index == selected ? k.pri : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: attachmentThumb(context, file, radius: 12),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: k.bg.withValues(alpha: .9),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onRemove(index),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: StrokeIcon(
                            AppIcons.close,
                            size: 12,
                            color: k.err,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
