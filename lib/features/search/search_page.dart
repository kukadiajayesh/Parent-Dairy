import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';

/// Search across the diary, grouped by record type. The design shows a
/// "Worksheets · 2 / Classwork · 0" layout with a per-group empty state.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<DiaryRecord> _match(List<DiaryRecord> source) {
    final query = _controller.text.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return source
        .where((r) =>
            r.title.toLowerCase().contains(query) ||
            r.subject.toLowerCase().contains(query) ||
            r.notes.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final hasQuery = _controller.text.trim().isNotEmpty;
    final worksheets = _match(state.worksheets);
    final classwork = _match(state.classwork);

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 50,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: k.surf,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _focus.hasFocus || hasQuery ? k.pri : k.bd3,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          StrokeIcon(AppIcons.search, size: 19, color: k.pri),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              onChanged: (_) => setState(() {}),
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w500,
                                color: k.tx2,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: 'Search worksheets and classwork',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                  color: k.tx5,
                                ),
                              ),
                            ),
                          ),
                          if (hasQuery)
                            InkWell(
                              onTap: () {
                                _controller.clear();
                                setState(() {});
                              },
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: StrokeIcon(
                                  AppIcons.close,
                                  size: 17,
                                  color: k.tx4,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: k.pri,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
                children: [
                  _ResultGroup(
                    label: 'Worksheets',
                    records: worksheets,
                    showEmpty: hasQuery,
                  ),
                  const SizedBox(height: 18),
                  _ResultGroup(
                    label: 'Classwork',
                    records: classwork,
                    showEmpty: hasQuery,
                  ),
                  // The design adds an "Exams · n" group behind showExamMarks.
                  if (!hasQuery) ...[
                    const SizedBox(height: 18),
                    const _SearchHint(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultGroup extends StatelessWidget {
  const _ResultGroup({
    required this.label,
    required this.records,
    required this.showEmpty,
  });

  final String label;
  final List<DiaryRecord> records;
  final bool showEmpty;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty && !showEmpty) return const SizedBox.shrink();

    final k = context.t;
    final state = AppScope.of(context);
    final root = Navigator.of(context, rootNavigator: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('$label · ${records.length}'),
        const SizedBox(height: 10),
        if (records.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
            decoration: BoxDecoration(
              color: k.surf2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                StrokeIcon(AppIcons.search, size: 26, color: k.tx5, strokeWidth: 1.8),
                const SizedBox(height: 6),
                Text(
                  'No academic records found.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: k.tx3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Try a different subject or clear the filters.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: k.tx4),
                ),
              ],
            ),
          )
        else
          for (final record in records) ...[
            AppCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              onTap: () => root.pushNamed(
                record.isWorksheet
                    ? Routes.worksheetDetail
                    : Routes.classworkDetail,
                arguments: record.id,
              ),
              child: Row(
                children: [
                  Builder(
                    builder: (context) {
                      final subject = state.subjectByName(record.subject);
                      return SubjectBadge(abbr: subject.abbr, hue: subject.hue);
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                          record.isWorksheet
                              ? '${AppDate.full(record.date)} · ${record.status.label}'
                              : '${AppDate.full(record.date)} · '
                                  '${AppFormat.photoCount(record.attachments.length)}',
                          style: TextStyle(fontSize: 12, color: k.tx4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _SearchHint extends StatelessWidget {
  const _SearchHint();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
      decoration: BoxDecoration(
        color: k.surf2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          StrokeIcon(AppIcons.search, size: 26, color: k.tx5, strokeWidth: 1.8),
          const SizedBox(height: 6),
          Text(
            'Search the diary',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: k.tx3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Find worksheets and classwork by title, subject or notes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: k.tx4),
          ),
        ],
      ),
    );
  }
}

/// Exam results appear in search only while the flag is on.
const bool searchIncludesExams = kShowExamMarks;
