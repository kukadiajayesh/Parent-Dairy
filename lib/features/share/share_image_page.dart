import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// "Create Academic Record" — the destination when an image is shared into the
/// app. A segmented control picks worksheet or classwork; the rest of the form
/// follows that choice.
class ShareImagePage extends StatefulWidget {
  const ShareImagePage({super.key});

  @override
  State<ShareImagePage> createState() => _ShareImagePageState();
}

class _ShareImagePageState extends State<ShareImagePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  RecordType _type = RecordType.worksheet;
  String _subject = 'Mathematics';
  DateTime _date = DateTime(2026, 8, 23);
  DateTime? _dueDate;
  bool _hasAnswerKey = false;

  bool get _isWorksheet => _type == RecordType.worksheet;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save({required bool addAnother}) {
    final state = AppScope.read(context);
    final title = _title.text.trim();

    state.addRecord(
      DiaryRecord(
        id: '${_isWorksheet ? 'ws' : 'cw'}-'
            '${DateTime.now().microsecondsSinceEpoch}',
        type: _type,
        subject: _subject,
        title: title.isEmpty
            ? (_isWorksheet ? 'Shared worksheet' : 'Shared classwork')
            : title,
        date: _date,
        dueDate: _isWorksheet ? _dueDate : null,
        notes: _isWorksheet ? '' : _notes.text.trim(),
        attachments: const [
          Attachment(name: 'shared-image.jpg', meta: 'Shared image'),
        ],
        answerKey: _isWorksheet && _hasAnswerKey
            ? const Attachment(
                name: 'answer-key.pdf',
                meta: '1 page · 240 KB',
                isPdf: true,
              )
            : null,
      ),
    );

    if (addAnother) {
      setState(() {
        _title.clear();
        _notes.clear();
        _dueDate = null;
        _hasAnswerKey = false;
      });
      AppToast.show(
        context,
        title: 'Record saved',
        description: 'Ready for the next image.',
      );
      return;
    }

    Navigator.of(context).pop();
    AppToast.show(
      context,
      title: 'Record saved',
      description: 'Image saved to your timeline.',
    );
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
                  const ImageSlot(
                    placeholder: 'Shared image from WhatsApp',
                    radius: 20,
                    height: 250,
                  ),
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
                  AppTextField(
                    label: 'Title',
                    controller: _title,
                    hintText: 'Optional — e.g. Fractions Practice',
                  ),
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
                      onTap: () async {
                        final added = await Navigator.of(context)
                            .pushNamed<int>(Routes.picker);
                        if (added != null && added > 0) {
                          setState(() => _hasAnswerKey = true);
                        }
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: k.surf2,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: StrokeIcon(
                              _hasAnswerKey ? AppIcons.check : AppIcons.plus,
                              size: 19,
                              color: _hasAnswerKey ? k.sec : k.tx3,
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
                    label: 'Save',
                    height: 54,
                    onPressed: () => _save(addAnother: false),
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
                    onPressed: () => _save(addAnother: true),
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
