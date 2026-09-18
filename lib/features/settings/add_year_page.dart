import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../children/child_switcher_sheet.dart';

/// Add Academic Year: label, span, target child, active + carry-over toggles.
class AddYearPage extends StatefulWidget {
  const AddYearPage({super.key});

  @override
  State<AddYearPage> createState() => _AddYearPageState();
}

class _AddYearPageState extends State<AddYearPage> {
  final TextEditingController _label = TextEditingController(text: '2027–28');

  DateTime _start = DateTime(2027, 4);
  DateTime _end = DateTime(2028, 3);
  bool _makeActive = true;
  bool _carryOver = true;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickMonth({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final label = _label.text.trim();

    try {
      await state.addYear(
        AcademicYear(
          label: label,
          span: '${AppDate.monthYear(_start)} – ${AppDate.monthYear(_end)}',
          records: 0,
          active: _makeActive,
        ),
        makeActive: _makeActive,
      );
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Academic year added',
        description: '$label is ready for new records.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't add year");
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Add Academic Year'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  AppTextField(
                    label: 'Academic year',
                    controller: _label,
                    hintText: '2027–28',
                    helperText:
                        'Written the way your school does, e.g. 2027–28.',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Starts',
                          value: AppDate.monthYear(_start),
                          trailing: PickerTrailing.calendar,
                          onTap: () => _pickMonth(isStart: true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'Ends',
                          value: AppDate.monthYear(_end),
                          trailing: PickerTrailing.calendar,
                          onTap: () => _pickMonth(isStart: false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('For child'),
                  const SizedBox(height: 6),
                  PressDip(
                    child: Material(
                      color: k.surf2,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: k.bd3, width: 1.5),
                      ),
                      child: AppInkWell(
                        onTap: () => ChildSwitcherSheet.show(context),
                        child: Container(
                          height: 64,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Monogram(initials: child.initials),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      child.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Currently ${child.grade} ${child.section}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: k.tx3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              StrokeIcon(
                                AppIcons.caretDown,
                                size: 16,
                                color: k.tx3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ToggleCard(
                    title: 'Make this the active year',
                    description: 'New records are saved here',
                    value: _makeActive,
                    onChanged: (v) => setState(() => _makeActive = v),
                  ),
                  const SizedBox(height: 12),
                  _ToggleCard(
                    title: 'Carry over subjects',
                    description: 'Copy the ${state.subjects.length} subjects '
                        'from ${state.activeYear}',
                    value: _carryOver,
                    onChanged: (v) => setState(() => _carryOver = v),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: k.priC,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        StrokeIcon(AppIcons.info, size: 19, color: k.priInk),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Records from earlier years stay exactly where '
                            'they are.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: k.priInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: 'Save Academic Year',
                onPressed: (_saving || _label.text.trim().isEmpty)
                    ? null
                    : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppInkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: k.surf2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            AppSwitch(value: value, onChanged: onChanged),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: k.tx3),
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
