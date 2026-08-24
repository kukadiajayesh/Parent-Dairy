import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// "Let's add your child" — also reached in edit mode from Manage Children.
class ChildSetupPage extends StatefulWidget {
  const ChildSetupPage({super.key, this.child});

  final Child? child;

  @override
  State<ChildSetupPage> createState() => _ChildSetupPageState();
}

class _ChildSetupPageState extends State<ChildSetupPage> {
  late final TextEditingController _name =
      TextEditingController(text: widget.child?.name ?? '');
  late final TextEditingController _school =
      TextEditingController(text: widget.child?.school ?? '');

  late String _grade = widget.child?.grade ?? 'Class 5';
  late String _section = widget.child?.section ?? 'B';
  late String _year = widget.child?.year ?? '2026–27';

  bool get _isEditing => widget.child != null;

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _pick({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _OptionSheet(
        title: title,
        options: options,
        current: current,
      ),
    );
    if (choice != null) onSelected(choice);
  }

  void _continue() {
    if (_isEditing) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.shell, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final years = state.years.map((y) => y.label).toList();

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_isEditing)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: ScreenHeader(title: 'Edit child'),
              ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, _isEditing ? 8 : 22, 20, 24),
                children: [
                  if (!_isEditing) ...[
                    const Text(
                      "Let's add your child",
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You can add more children any time.',
                      style: TextStyle(fontSize: 14, height: 1.5, color: k.tx3),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Row(
                    children: [
                      InkWell(
                        onTap: () {},
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k.surf2,
                            shape: BoxShape.circle,
                          ),
                          foregroundDecoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: DashedBorder(color: k.bd5),
                          ),
                          child: StrokeIcon(
                            AppIcons.camera,
                            size: 24,
                            color: k.tx4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profile photo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Optional',
                            style: TextStyle(fontSize: 12.5, color: k.tx4),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Child name',
                    controller: _name,
                    hintText: 'Aarav Patel',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'School name',
                    controller: _school,
                    hintText: 'Sunrise English School',
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: PickerField(
                          label: 'Class',
                          value: _grade,
                          onTap: () => _pick(
                            title: 'Class',
                            options: [
                              for (var i = 1; i <= 12; i++) 'Class $i',
                            ],
                            current: _grade,
                            onSelected: (v) => setState(() => _grade = v),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PickerField(
                          label: 'Section',
                          value: _section,
                          onTap: () => _pick(
                            title: 'Section',
                            options: const ['A', 'B', 'C', 'D'],
                            current: _section,
                            onSelected: (v) => setState(() => _section = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PickerField(
                    label: 'Academic year',
                    value: _year,
                    onTap: () => _pick(
                      title: 'Academic year',
                      options: years,
                      current: _year,
                      onSelected: (v) => setState(() => _year = v),
                    ),
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: _isEditing ? 'Save changes' : 'Continue',
                onPressed: _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple single-choice sheet backing the class / section / year pickers.
class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;
  final List<String> options;
  final String current;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: k.bd4,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected = option == current;
                  return AppCard(
                    radius: 16,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    background: selected ? k.priC : k.surf,
                    borderColor: selected ? k.priFill : k.bd,
                    onTap: () => Navigator.of(context).pop(option),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected ? k.priInk : k.tx,
                            ),
                          ),
                        ),
                        if (selected)
                          StrokeIcon(AppIcons.check, size: 18, color: k.pri),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
