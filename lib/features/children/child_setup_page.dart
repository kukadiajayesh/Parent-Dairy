import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../picker/attachment_source_row.dart';

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
  late String _year = widget.child?.year ?? _defaultYearLabel();

  PickedAttachment? _photo;
  bool _saving = false;

  bool get _isEditing => widget.child != null;

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _school.text.trim().isNotEmpty;

  /// The Indian school year turns over in April, so a January launch should
  /// still default to the year that started last April.
  static String _defaultYearLabel() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    final endShort = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return '$startYear–$endShort';
  }

  /// Offered when the account has no years yet — the very first child cannot
  /// pick from a list that Firestore has not been seeded with.
  static List<String> _fallbackYears() {
    final now = DateTime.now();
    final startYear = now.month >= 4 ? now.year : now.year - 1;
    return [
      for (var offset = 1; offset >= -3; offset--)
        '${startYear + offset}–'
            '${((startYear + offset + 1) % 100).toString().padLeft(2, '0')}',
    ];
  }

  /// The freshly picked file if there is one, otherwise the stored avatar.
  ImageProvider? get _photoImage {
    final local = fileImage(_photo?.path);
    if (local != null) return local;
    final url = widget.child?.photoUrl;
    return (url == null || url.isEmpty) ? null : NetworkImage(url);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      useSafeArea: true,
      builder: (context) => const _PhotoSourceSheet(),
    );
    if (source == null || !mounted) return;

    try {
      final picked = source == AttachmentSource.camera
          ? await ImageService.capture()
          : (await ImageService.pickFromGallery(multiple: false)).firstOrNull;
      if (picked == null || !mounted) return;
      setState(() => _photo = picked);
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't add photo");
    }
  }

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

  Future<void> _continue() async {
    if (!_canSave) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final state = AppScope.read(context);
    final name = _name.text.trim();

    try {
      await state.saveChild(
        Child(
          id: widget.child?.id ?? '',
          name: name,
          initials: Child.initialsFor(name),
          school: _school.text.trim(),
          grade: _grade,
          section: _section,
          year: _year,
          photoUrl: widget.child?.photoUrl,
        ),
        photo: _photo,
      );
      if (!mounted) return;

      if (_isEditing) {
        navigator.pop();
        return;
      }
      navigator.pushNamedAndRemoveUntil(Routes.shell, (_) => false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save child");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final years = state.years.isEmpty
        ? _fallbackYears()
        : state.years.map((y) => y.label).toList();

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
                        onTap: _pickPhoto,
                        customBorder: const CircleBorder(),
                        child: Container(
                          width: 72,
                          height: 72,
                          alignment: Alignment.center,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            color: k.surf2,
                            shape: BoxShape.circle,
                            image: _photoImage == null
                                ? null
                                : DecorationImage(
                                    image: _photoImage!,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          foregroundDecoration: _photoImage != null
                              ? null
                              : BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: DashedBorder(color: k.bd5),
                                ),
                          child: _photoImage != null
                              ? null
                              : StrokeIcon(
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
                            _photoImage == null ? 'Optional' : 'Tap to change',
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
                label: _saving
                    ? 'Saving…'
                    : (_isEditing ? 'Save changes' : 'Continue'),
                onPressed: _canSave ? _continue : null,
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

/// Camera / Gallery choice for the profile photo.
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

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
            const Text(
              'Profile photo',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 14),
            AttachmentSourceRow(
              emphasizeFirst: true,
              onPick: (source) => Navigator.of(context).pop(source),
            ),
          ],
        ),
      ),
    );
  }
}
