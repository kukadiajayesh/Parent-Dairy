import 'package:flutter/material.dart';

import '../core/theme/subject_hue.dart';
import 'models.dart';
import 'sample_data.dart';

/// Timeline filter axes, mirroring the design's `timelineFilter` rows.
class TimelineFilter {
  const TimelineFilter({
    this.subject = 'All',
    this.type = 'All',
    this.date = 'This week',
  });

  final String subject;
  final String type;
  final String date;

  String get summary => '$subject · $type · $date';

  bool get isDefault => subject == 'All' && type == 'All' && date == 'This week';

  TimelineFilter copyWith({String? subject, String? type, String? date}) =>
      TimelineFilter(
        subject: subject ?? this.subject,
        type: type ?? this.type,
        date: date ?? this.date,
      );
}

/// Single source of truth for everything the screens read and mutate.
///
/// Deliberately plain: one [ChangeNotifier] handed down by [AppScope]. There is
/// no persistence layer yet, so saving a record updates this list and nothing
/// else — which is exactly what the prototype does.
class AppState extends ChangeNotifier {
  AppState()
      : _subjects = List.of(SampleData.subjects),
        _records = List.of(SampleData.allRecords),
        _years = List.of(SampleData.years);

  // ── Theme ────────────────────────────────────────────────────────────────
  bool _dark = false;
  bool get isDark => _dark;
  ThemeMode get themeMode => _dark ? ThemeMode.dark : ThemeMode.light;
  String get themeLabel => _dark ? 'Dark' : 'Light';
  void toggleTheme() {
    _dark = !_dark;
    notifyListeners();
  }

  // ── Child / year selection ───────────────────────────────────────────────
  final List<Child> _children = List.of(SampleData.children);
  List<Child> get children => List.unmodifiable(_children);

  int _childIndex = 0;
  Child get activeChild => _children[_childIndex];
  void selectChild(int index) {
    if (index == _childIndex) return;
    _childIndex = index;
    notifyListeners();
  }

  List<AcademicYear> _years;
  List<AcademicYear> get years => List.unmodifiable(_years);

  String _activeYear = SampleData.years.first.label;
  String get activeYear => _activeYear;
  void selectYear(String label) {
    if (label == _activeYear) return;
    _activeYear = label;
    notifyListeners();
  }

  void addYear(AcademicYear year, {required bool makeActive}) {
    _years = [year, ..._years];
    if (makeActive) _activeYear = year.label;
    notifyListeners();
  }

  // ── Subjects ─────────────────────────────────────────────────────────────
  List<Subject> _subjects;
  List<Subject> get subjects => List.unmodifiable(_subjects);
  List<String> get subjectNames => _subjects.map((s) => s.name).toList();

  Subject subjectByName(String name) => _subjects.firstWhere(
        (s) => s.name == name,
        orElse: () => Subject(
          name: name,
          abbr: name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase(),
          hue: SubjectHue.stone,
          order: _subjects.length + 1,
        ),
      );

  void addSubject(Subject subject) {
    _subjects = [..._subjects, subject];
    notifyListeners();
  }

  void removeSubject(String name) {
    _subjects = _subjects.where((s) => s.name != name).toList();
    notifyListeners();
  }

  // ── Records ──────────────────────────────────────────────────────────────
  List<DiaryRecord> _records;
  List<DiaryRecord> get records => List.unmodifiable(_records);

  List<DiaryRecord> get worksheets =>
      _records.where((r) => r.type == RecordType.worksheet).toList();

  List<DiaryRecord> get classwork =>
      _records.where((r) => r.type == RecordType.classwork).toList();

  /// Newest first — the order the timeline and "Recent activity" use.
  List<DiaryRecord> get recordsByDateDesc =>
      _records.toList()..sort((a, b) => b.date.compareTo(a.date));

  List<DiaryRecord> get pendingWorksheets => worksheets
      .where((w) => w.status == WorksheetStatus.pending)
      .toList()
    ..sort((a, b) =>
        (a.dueDate ?? a.date).compareTo(b.dueDate ?? b.date));

  DiaryRecord? recordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  void addRecord(DiaryRecord record) {
    _records = [record, ..._records];
    notifyListeners();
  }

  void deleteRecord(String id) {
    _records = _records.where((r) => r.id != id).toList();
    notifyListeners();
  }

  void markCompleted(String id) {
    _records = [
      for (final r in _records)
        if (r.id == id)
          DiaryRecord(
            id: r.id,
            type: r.type,
            subject: r.subject,
            title: r.title,
            date: r.date,
            dueDate: r.dueDate,
            completedDate: DateTime.now(),
            notes: r.notes,
            status: WorksheetStatus.completed,
            attachments: r.attachments,
            answerKey: r.answerKey,
          )
        else
          r,
    ];
    notifyListeners();
  }

  // ── Timeline / list filters ──────────────────────────────────────────────
  TimelineFilter _filter = const TimelineFilter();
  TimelineFilter get filter => _filter;
  void setFilter(TimelineFilter value) {
    _filter = value;
    notifyListeners();
  }

  void clearFilter() => setFilter(const TimelineFilter());

  String _worksheetStatusFilter = 'All';
  String get worksheetStatusFilter => _worksheetStatusFilter;
  void setWorksheetStatusFilter(String value) {
    _worksheetStatusFilter = value;
    notifyListeners();
  }

  String _listSubject = 'All';
  String get listSubject => _listSubject;
  void setListSubject(String value) {
    _listSubject = value;
    notifyListeners();
  }

  // ── Connectivity banner ──────────────────────────────────────────────────
  bool _offline = false;
  bool get isOffline => _offline;
  void toggleOffline() {
    _offline = !_offline;
    notifyListeners();
  }

  void setOffline(bool value) {
    if (_offline == value) return;
    _offline = value;
    notifyListeners();
  }

  /// Groups records by subject in the configured subject order, dropping empty
  /// groups — the `groupBy` helper from the prototype.
  List<SubjectGroup> groupBySubject(List<DiaryRecord> source, String unit) {
    final names =
        _listSubject == 'All' ? subjectNames : <String>[_listSubject];
    final groups = <SubjectGroup>[];
    for (final name in names) {
      final items = source.where((r) => r.subject == name).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (items.isEmpty) continue;
      groups.add(
        SubjectGroup(
          subject: subjectByName(name),
          items: items,
          count: '${items.length} $unit${items.length == 1 ? '' : 's'}',
        ),
      );
    }
    return groups;
  }
}

class SubjectGroup {
  const SubjectGroup({
    required this.subject,
    required this.items,
    required this.count,
  });

  final Subject subject;
  final List<DiaryRecord> items;
  final String count;
}

/// Makes [AppState] available to the widget tree and rebuilds dependents when
/// it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }

  /// Reads the state without subscribing — for callbacks that only mutate.
  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget');
    return scope!.notifier!;
  }
}
