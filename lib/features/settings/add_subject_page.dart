import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/subject_hue.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Add Subject: live preview card, name, colour tag, order, code and active.
class AddSubjectPage extends StatefulWidget {
  const AddSubjectPage({super.key});

  @override
  State<AddSubjectPage> createState() => _AddSubjectPageState();
}

class _AddSubjectPageState extends State<AddSubjectPage> {
  final TextEditingController _name = TextEditingController(text: 'Computer');

  SubjectHue _hue = SubjectHue.steel;
  bool _active = true;

  String get _displayName =>
      _name.text.trim().isEmpty ? 'New subject' : _name.text.trim();

  String get _abbr => _displayName.length >= 2
      ? _displayName.substring(0, 2).toUpperCase()
      : _displayName.toUpperCase();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _displayName;

    try {
      await state.addSubject(
        Subject(
          name: name,
          abbr: _abbr,
          hue: _hue,
          order: state.subjects.length + 1,
          active: _active,
        ),
      );
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Subject added',
        description: '$name is now available when adding records.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't add subject");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final nextOrder = '${state.subjects.length + 1}';

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Add Subject'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        SubjectBadge(
                          abbr: _abbr,
                          hue: _hue,
                          size: 52,
                          fontSize: 15,
                          radius: 16,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Preview — how it appears on cards and chips',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: k.tx4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SubjectTag(name: 'Chip', hue: _hue),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Subject name',
                    controller: _name,
                    hintText: 'EVS',
                    helperText:
                        'Use the name your school uses, e.g. EVS or Sanskrit.',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  const FieldLabel('Colour tag'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final hue in SubjectHue.values)
                        _HueSwatch(
                          hue: hue,
                          selected: _hue == hue,
                          onTap: () => setState(() => _hue = hue),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Each subject keeps one fixed colour across the diary.',
                    style: TextStyle(fontSize: 12, color: k.tx4),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Display order',
                          value: nextOrder,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Short code'),
                            const SizedBox(height: 6),
                            Container(
                              height: 56,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: k.surf2,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: k.bd3, width: 1.5),
                              ),
                              child: Text(
                                _abbr,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ToggleRow(
                    title: 'Active',
                    description: 'Show this subject when adding records',
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: 'Save Subject',
                onPressed: (_saving || _name.text.trim().isEmpty)
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

class _HueSwatch extends StatelessWidget {
  const _HueSwatch({
    required this.hue,
    required this.selected,
    required this.onTap,
  });

  final SubjectHue hue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Tooltip(
      message: hue.label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? hue.dot(k) : Colors.transparent,
              width: 2.5,
            ),
          ),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: hue.dot(k),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
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
    return InkWell(
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
