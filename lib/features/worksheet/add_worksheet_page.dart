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
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/repositories/attachment_repository.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';

/// Add / edit a worksheet: subject, title, dates, notes, attachments, answer
/// key and status.
class AddWorksheetPage extends StatefulWidget {
  const AddWorksheetPage({super.key, this.existing});

  final DiaryRecord? existing;

  @override
  State<AddWorksheetPage> createState() => _AddWorksheetPageState();
}

class _AddWorksheetPageState extends State<AddWorksheetPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  String? _subject;

  /// §37: today, not a fixed sample date — a parent recording a worksheet is
  /// almost always recording today's.
  late DateTime _date = widget.existing?.date ?? DateUtils.dateOnly(DateTime.now());
  late DateTime? _dueDate = widget.existing?.dueDate;
  late WorksheetStatus _status =
      widget.existing?.status ?? WorksheetStatus.pending;
  late final List<Attachment> _attachments =
      List.of(widget.existing?.attachments ?? const []);
  late Attachment? _answerKey = widget.existing?.answerKey;

  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _canSave =>
      !_saving && _title.text.trim().isNotEmpty && _subject != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-selects the last subject used (§11), once subjects have loaded.
    if (_subject != null) return;
    final state = AppScope.of(context);
    final suggested = widget.existing?.subject ?? state.suggestedSubject;
    if (suggested.isNotEmpty) _subject = suggested;
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isDue}) async {
    final initial = isDue ? (_dueDate ?? _date) : _date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (isDue) {
        _dueDate = picked;
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _addAttachment([AttachmentSource? source]) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) => PickerPage(initialSource: source),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() {
      for (final file in picked) {
        _attachments.add(
          AttachmentRepository.stage(
            file,
            caption: 'Page ${_attachments.length + 1}',
          ),
        );
      }
    });
  }

  Future<void> _addAnswerKey(AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) =>
            PickerPage(initialSource: source, allowMultiple: false),
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

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final subject = _subject!;

    final record = DiaryRecord(
      // Empty id means "create"; the repository assigns the Firestore id.
      id: widget.existing?.id ?? '',
      childId: widget.existing?.childId ?? '',
      academicYearId: widget.existing?.academicYearId ?? state.activeYear,
      type: RecordType.worksheet,
      subject: subject,
      title: _title.text.trim(),
      date: _date,
      dueDate: _dueDate,
      completedDate: _status == WorksheetStatus.completed
          ? (widget.existing?.completedDate ?? DateTime.now())
          : null,
      notes: _notes.text.trim(),
      status: _status,
      attachments: _attachments,
      answerKey: _answerKey,
      createdAt: widget.existing?.createdAt,
    );

    try {
      await state.saveRecord(record);
      if (!mounted) return;
      navigator.pop();
      // Captured before the await: this page is gone by the time the toast
      // shows, so its own context can no longer resolve a messenger.
      AppToast.showOn(
        messenger,
        context,
        title: _isEditing ? 'Worksheet updated' : 'Worksheet saved',
        description: '$subject worksheet added to your timeline.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save worksheet");
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
                title: _isEditing ? 'Edit Worksheet' : 'Add Worksheet',
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
                    label: 'Worksheet title',
                    controller: _title,
                    hintText: 'Fractions Practice',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Date',
                          value: AppDate.full(_date),
                          trailing: PickerTrailing.calendar,
                          onTap: () => _pickDate(isDue: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'Due date',
                          value: _dueDate == null
                              ? 'Optional'
                              : AppDate.full(_dueDate!),
                          isPlaceholder: _dueDate == null,
                          trailing: PickerTrailing.calendar,
                          onTap: () => _pickDate(isDue: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Notes',
                    controller: _notes,
                    hintText: 'Pages 24–25, show working',
                    maxLines: 3,
                    minHeight: 66,
                  ),
                  const SizedBox(height: 18),
                  const HairLine(),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Worksheet',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        AppFormat.fileCount(_attachments.length),
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
                    onPick: _addAttachment,
                  ),
                  const SizedBox(height: 10),
                  _AttachmentGrid(
                    attachments: _attachments,
                    onRemove: (index) =>
                        setState(() => _attachments.removeAt(index)),
                    onAdd: _addAttachment,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Text(
                        'Answer key',
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
                  AttachmentSourceRow(onPick: _addAnswerKey),
                  if (_answerKey != null) ...[
                    const SizedBox(height: 10),
                    _AnswerKeyRow(
                      attachment: _answerKey!,
                      onRemove: () => setState(() => _answerKey = null),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FieldLabel('Status'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final status in WorksheetStatus.values) ...[
                        _StatusChip(
                          status: status,
                          selected: _status == status,
                          onTap: () => setState(() => _status = status),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: _saving
                    ? 'Saving…'
                    : (_isEditing ? 'Save Changes' : 'Save Worksheet'),
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final WorksheetStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final pending = status == WorksheetStatus.pending;
    final background =
        selected ? (pending ? k.warnC : k.subSciC) : k.surf;
    final border = selected ? (pending ? k.warn : k.subSciInk) : k.bd3;
    final ink = selected ? (pending ? k.warnInk : k.subSciInk) : k.tx3;
    final dot = selected ? (pending ? k.warn : const Color(0xFF3E8168)) : k.bd5;

    return Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: border, width: 1.5)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Dot(color: dot, size: 7),
              const SizedBox(width: 7),
              Text(
                status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentGrid extends StatelessWidget {
  const _AttachmentGrid({
    required this.attachments,
    required this.onRemove,
    required this.onAdd,
  });

  final List<Attachment> attachments;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: [
        for (var i = 0; i < attachments.length; i++)
          Stack(
            fit: StackFit.expand,
            children: [
              ImageSlot(
                placeholder: attachments[i].isPdf
                    ? attachments[i].name
                    : attachments[i].meta,
                image: attachmentImage(attachments[i]),
                radius: 14,
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Material(
                  color: k.bg.withValues(alpha: .9),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onRemove(i),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: StrokeIcon(
                        AppIcons.close,
                        size: 14,
                        color: k.err,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(14),
          child: DashedContainer(
            radius: 14,
            padding: EdgeInsets.zero,
            color: k.bd4,
            background: k.surf2,
            child: Center(
              child: StrokeIcon(AppIcons.plus, size: 20, color: k.tx4),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnswerKeyRow extends StatelessWidget {
  const _AnswerKeyRow({required this.attachment, required this.onRemove});

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.surf2,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: attachment.isPdf
                ? Text(
                    'PDF',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: k.tx3,
                    ),
                  )
                : ImageSlot(
                    image: attachmentImage(attachment),
                    placeholder: '',
                    showCaption: false,
                    radius: 12,
                    width: 52,
                    height: 52,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  attachment.meta,
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
              ],
            ),
          ),
          AppIconButton(
            size: 34,
            borderRadius: 10,
            hoverBackground: k.errC,
            onTap: onRemove,
            tooltip: 'Remove',
            child: StrokeIcon(AppIcons.close, size: 17, color: k.err),
          ),
        ],
      ),
    );
  }
}
