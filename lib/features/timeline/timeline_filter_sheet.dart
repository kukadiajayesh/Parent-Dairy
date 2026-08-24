import 'package:flutter/material.dart';

import '../../core/config/feature_flags.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';

/// "Filter timeline" sheet — subject, type and date axes plus Clear / Apply.
/// Edits are held locally so Cancel-by-dismiss leaves the timeline untouched.
abstract final class TimelineFilterSheet {
  static Future<void> show(BuildContext context) async {
    final state = AppScope.read(context);
    final messengerContext = context;

    await AppSheet.show(context, (sheetContext) {
      return _FilterSheetBody(
        state: state,
        onApply: (filter) {
          state.setFilter(filter);
          Navigator.of(sheetContext).pop();
          AppToast.show(
            messengerContext,
            title: 'Filters applied',
            description: 'Showing ${filter.type.toLowerCase()} records, '
                '${filter.date.toLowerCase()}.',
          );
        },
      );
    });
  }
}

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({required this.state, required this.onApply});

  final AppState state;
  final ValueChanged<TimelineFilter> onApply;

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late TimelineFilter _draft = widget.state.filter;

  static const _dates = ['Today', 'This week', 'This month', 'Custom'];

  List<String> get _types => [
        'All',
        'Worksheet',
        'Classwork',
        // Exam and Marks join this row when showExamMarks is on.
        if (kShowExamMarks) ...['Exam', 'Marks'],
      ];

  @override
  Widget build(BuildContext context) {
    final subjects = ['All', ...widget.state.subjectNames];

    return AppSheet(
      title: 'Filter timeline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Group(
            label: 'Subject',
            options: subjects,
            selected: _draft.subject,
            onSelected: (v) => setState(() => _draft = _draft.copyWith(subject: v)),
          ),
          const SizedBox(height: 16),
          _Group(
            label: 'Type',
            options: _types,
            selected: _draft.type,
            onSelected: (v) => setState(() => _draft = _draft.copyWith(type: v)),
          ),
          const SizedBox(height: 16),
          _Group(
            label: 'Date',
            options: _dates,
            selected: _draft.date,
            onSelected: (v) => setState(() => _draft = _draft.copyWith(date: v)),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                flex: 10,
                child: AppOutlinedButton(
                  label: 'Clear',
                  height: 50,
                  borderRadius: 15,
                  onPressed: () =>
                      setState(() => _draft = const TimelineFilter()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 14,
                child: AppFilledButton(
                  label: 'Apply',
                  height: 50,
                  elevated: false,
                  onPressed: () => widget.onApply(_draft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              AppChip(
                label: option,
                selected: option == selected,
                onTap: () => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}
