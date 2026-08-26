import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Picks which existing worksheet the shared [file] should become the answer
/// key of. Reached from [ShareChooserPage].
class AttachAnswerKeyPage extends StatefulWidget {
  const AttachAnswerKeyPage({super.key, required this.file});

  final PickedAttachment file;

  @override
  State<AttachAnswerKeyPage> createState() => _AttachAnswerKeyPageState();
}

class _AttachAnswerKeyPageState extends State<AttachAnswerKeyPage> {
  final TextEditingController _query = TextEditingController();
  DiaryRecord? _saving;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _attach(DiaryRecord record) async {
    if (_saving != null) return;
    setState(() => _saving = record);

    final state = AppScope.read(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.saveRecord(record, newAnswerKey: widget.file);
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Answer key attached',
        description: '${record.title} now has an answer key.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = null);
      AppToast.failure(context, error, title: "Couldn't attach answer key");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final query = _query.text.trim().toLowerCase();

    final worksheets = state.worksheets.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final filtered = query.isEmpty
        ? worksheets
        : worksheets
              .where(
                (w) =>
                    w.title.toLowerCase().contains(query) ||
                    w.subject.toLowerCase().contains(query),
              )
              .toList();

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Choose a worksheet'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: k.surf,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: k.bd3, width: 1.5),
                ),
                child: Row(
                  children: [
                    StrokeIcon(AppIcons.search, size: 19, color: k.tx4),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(fontSize: 14.5, color: k.tx2),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Search worksheets',
                          hintStyle: TextStyle(fontSize: 14.5, color: k.tx5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyListNotice(
                      title: 'No worksheets found',
                      description:
                          'Save a worksheet first, then attach an answer key to it.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final record = filtered[index];
                        final subject = state.subjectByName(record.subject);
                        return AppCard(
                          radius: 16,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          onTap: () => _attach(record),
                          child: Row(
                            children: [
                              SubjectBadge(
                                abbr: subject.abbr,
                                hue: subject.hue,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      record.hasAnswerKey
                                          ? '${AppDate.full(record.date)} · replaces existing key'
                                          : AppDate.full(record.date),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: k.tx4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_saving?.id == record.id)
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: k.tx4,
                                  ),
                                )
                              else
                                StrokeIcon(
                                  AppIcons.forward,
                                  size: 16,
                                  color: k.tx4,
                                ),
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
