import '../core/theme/subject_hue.dart';
import 'models.dart';

/// Content transcribed from the prototype's `renderVals()` so the Flutter build
/// shows exactly what the design shows. Swap this file for a repository when a
/// backend lands — nothing above it knows where the data comes from.
abstract final class SampleData {
  static DateTime _d(int day, int month) => DateTime(2026, month, day);

  static const subjects = <Subject>[
    Subject(name: 'Mathematics', abbr: 'MA', hue: SubjectHue.indigo, order: 1),
    Subject(name: 'English', abbr: 'EN', hue: SubjectHue.terracotta, order: 2),
    Subject(name: 'Science', abbr: 'SC', hue: SubjectHue.green, order: 3),
    Subject(name: 'Gujarati', abbr: 'GU', hue: SubjectHue.ochre, order: 4),
    Subject(name: 'Hindi', abbr: 'HI', hue: SubjectHue.violet, order: 5),
  ];

  static const children = <Child>[
    Child(
      name: 'Aarav',
      initials: 'AR',
      school: 'Sunrise English School',
      grade: 'Class 5',
      section: 'B',
      year: '2026–27',
    ),
    Child(
      name: 'Diya',
      initials: 'DI',
      school: 'Sunrise English School',
      grade: 'Class 2',
      section: 'A',
      year: '2026–27',
    ),
  ];

  static const years = <AcademicYear>[
    AcademicYear(
      label: '2026–27',
      span: 'Apr 2026 – Mar 2027',
      records: 42,
      active: true,
    ),
    AcademicYear(label: '2025–26', span: 'Apr 2025 – Mar 2026', records: 118),
    AcademicYear(label: '2024–25', span: 'Apr 2024 – Mar 2025', records: 96),
  ];

  static const parentName = 'Jayesh';
  static const parentFullName = 'Jayesh Patel';
  static const parentEmail = 'jayesh.patel@gmail.com';
  static const parentInitials = 'JP';

  static final worksheets = <DiaryRecord>[
    DiaryRecord(
      id: 'ws-1',
      type: RecordType.worksheet,
      subject: 'Mathematics',
      title: 'Fractions Practice',
      date: _d(23, 8),
      dueDate: _d(28, 8),
      notes: 'Pages 24–25, show working. Teacher will check on Friday.',
      attachments: const [
        Attachment(name: 'fractions-page-1.jpg', meta: 'Page 1'),
        Attachment(name: 'fractions-page-2.jpg', meta: 'Page 2'),
      ],
      answerKey: const Attachment(
        name: 'answer-key-fractions.pdf',
        meta: '1 page · 240 KB',
        isPdf: true,
      ),
    ),
    DiaryRecord(
      id: 'ws-2',
      type: RecordType.worksheet,
      subject: 'English',
      title: 'Chapter 4 comprehension questions',
      date: _d(22, 8),
      dueDate: _d(31, 8),
      attachments: const [Attachment(name: 'english-ch4.jpg', meta: 'Page 1')],
    ),
    DiaryRecord(
      id: 'ws-3',
      type: RecordType.worksheet,
      subject: 'Science',
      title: 'Plants and animals — label diagram',
      date: _d(20, 8),
      dueDate: _d(1, 9),
      attachments: const [
        Attachment(name: 'plants-1.jpg', meta: 'Page 1'),
        Attachment(name: 'plants-2.jpg', meta: 'Page 2'),
      ],
    ),
    DiaryRecord(
      id: 'ws-4',
      type: RecordType.worksheet,
      subject: 'Gujarati',
      title: 'Homework — page 24, 25',
      date: _d(12, 8),
      completedDate: _d(14, 8),
      status: WorksheetStatus.completed,
      attachments: const [
        Attachment(name: 'gujarati-1.jpg', meta: 'Page 1'),
        Attachment(name: 'gujarati-2.jpg', meta: 'Page 2'),
      ],
    ),
    DiaryRecord(
      id: 'ws-5',
      type: RecordType.worksheet,
      subject: 'Mathematics',
      title: 'Multiplication drill — set 3',
      date: _d(4, 8),
      completedDate: _d(6, 8),
      status: WorksheetStatus.completed,
      attachments: const [
        Attachment(name: 'drill-1.jpg', meta: 'Page 1'),
        Attachment(name: 'drill-2.jpg', meta: 'Page 2'),
      ],
    ),
    DiaryRecord(
      id: 'ws-6',
      type: RecordType.worksheet,
      subject: 'English',
      title: 'Spelling list — week 6',
      date: _d(8, 8),
      completedDate: _d(9, 8),
      status: WorksheetStatus.completed,
      attachments: const [Attachment(name: 'spelling.jpg', meta: 'Page 1')],
    ),
  ];

  static final classwork = <DiaryRecord>[
    DiaryRecord(
      id: 'cw-1',
      type: RecordType.classwork,
      subject: 'English',
      title: 'Chapter 4 Questions',
      date: _d(23, 8),
      notes: 'Copied from board. Question 5 left incomplete.',
      attachments: const [
        Attachment(name: 'ch4-1.jpg', meta: 'Photo 1'),
        Attachment(name: 'ch4-2.jpg', meta: 'Photo 2'),
        Attachment(name: 'ch4-3.jpg', meta: 'Photo 3'),
      ],
    ),
    DiaryRecord(
      id: 'cw-2',
      type: RecordType.classwork,
      subject: 'Mathematics',
      title: 'Notebook — page 31',
      date: _d(22, 8),
      attachments: const [
        Attachment(name: 'nb31-1.jpg', meta: 'Photo 1'),
        Attachment(name: 'nb31-2.jpg', meta: 'Photo 2'),
        Attachment(name: 'nb31-3.jpg', meta: 'Photo 3'),
      ],
    ),
    DiaryRecord(
      id: 'cw-3',
      type: RecordType.classwork,
      subject: 'Hindi',
      title: 'Dictation practice',
      date: _d(21, 8),
      attachments: const [
        Attachment(name: 'dictation-1.jpg', meta: 'Photo 1'),
        Attachment(name: 'dictation-2.jpg', meta: 'Photo 2'),
      ],
    ),
    DiaryRecord(
      id: 'cw-4',
      type: RecordType.classwork,
      subject: 'Science',
      title: 'Leaf diagram — notebook',
      date: _d(20, 8),
      attachments: const [
        Attachment(name: 'leaf-1.jpg', meta: 'Photo 1'),
        Attachment(name: 'leaf-2.jpg', meta: 'Photo 2'),
      ],
    ),
    DiaryRecord(
      id: 'cw-5',
      type: RecordType.classwork,
      subject: 'Mathematics',
      title: 'Board work — decimals',
      date: _d(19, 8),
      attachments: const [
        Attachment(name: 'decimals-1.jpg', meta: 'Photo 1'),
        Attachment(name: 'decimals-2.jpg', meta: 'Photo 2'),
      ],
    ),
  ];

  static List<DiaryRecord> get allRecords => [...worksheets, ...classwork];
}
