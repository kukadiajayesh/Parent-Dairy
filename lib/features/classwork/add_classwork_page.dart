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

/// Add / edit classwork: subject, title, date, notes and a photo drop zone.
class AddClassworkPage extends StatefulWidget {
  const AddClassworkPage({super.key, this.existing});

  final DiaryRecord? existing;

  @override
  State<AddClassworkPage> createState() => _AddClassworkPageState();
}

class _AddClassworkPageState extends State<AddClassworkPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  late String _subject = widget.existing?.subject ?? 'English';
  late DateTime _date = widget.existing?.date ?? DateTime(2026, 8, 23);
  late final List<Attachment> _photos =
      List.of(widget.existing?.attachments ?? const []);

  bool get _isEditing => widget.existing != null;
  bool get _canSave => _title.text.trim().isNotEmpty;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final added = await Navigator.of(context).pushNamed<int>(Routes.picker);
    if (added == null || added == 0) return;
    setState(() {
      for (var i = 0; i < added; i++) {
        _photos.add(
          Attachment(
            name: 'classwork-${_photos.length + 1}.jpg',
            meta: 'Photo ${_photos.length + 1}',
          ),
        );
      }
    });
  }

  void _save() {
    final state = AppScope.read(context);
    final record = DiaryRecord(
      id: widget.existing?.id ??
          'cw-${DateTime.now().microsecondsSinceEpoch}',
      type: RecordType.classwork,
      subject: _subject,
      title: _title.text.trim(),
      date: _date,
      notes: _notes.text.trim(),
      attachments: _photos,
    );

    if (_isEditing) state.deleteRecord(record.id);
    state.addRecord(record);

    Navigator.of(context).pop();
    AppToast.show(
      context,
      title: _isEditing ? 'Classwork updated' : 'Classwork saved',
      description: '${AppFormat.photoCount(_photos.length)} added to '
          '$_subject classwork.',
    );
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
                  AppTextField(
                    label: 'Title',
                    controller: _title,
                    hintText: 'Chapter 4 Questions',
                    onChanged: (_) => setState(() {}),
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
                  _PhotoDropZone(onPick: _addPhotos),
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
                              ImageSlot(
                                placeholder: '${i + 1}',
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
                label: _isEditing ? 'Save Changes' : 'Save Classwork',
                onPressed: _canSave ? _save : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoDropZone extends StatelessWidget {
  const _PhotoDropZone({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return DashedContainer(
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.subSciC,
              borderRadius: BorderRadius.circular(16),
            ),
            child: StrokeIcon(AppIcons.camera, size: 24, color: k.subSciInk),
          ),
          const SizedBox(height: 6),
          const Text(
            'Add classwork photos',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Snap the notebook page or pick from gallery',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.5, color: k.tx3),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppFilledButton(
                  label: 'Camera',
                  height: 48,
                  elevated: false,
                  color: k.secFill,
                  hoverColor: k.secFillH,
                  onPressed: onPick,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppTonalButton(
                  label: 'Gallery',
                  height: 48,
                  fontSize: 14,
                  borderRadius: 14,
                  background: k.secC,
                  hoverBackground: k.secCH,
                  foreground: k.secInk,
                  onPressed: onPick,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
