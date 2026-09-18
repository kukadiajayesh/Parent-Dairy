import 'stroke_icon.dart';

/// Every icon path in `Parent Academic Diary.dc.html`, copied verbatim.
abstract final class AppIcons {
  /// Open book — app mark on splash and login.
  static const book = SvgIcon(
    [
      'M4 5.5A1.5 1.5 0 0 1 5.5 4H11v16H5.5A1.5 1.5 0 0 1 4 18.5z',
      'M20 5.5A1.5 1.5 0 0 0 18.5 4H13v16h5.5A1.5 1.5 0 0 0 20 18.5z',
      'M15.5 8.5h2.5M15.5 12h2.5M6 8.5h2.5M6 12h2.5',
    ],
    strokeWidth: 1.8,
  );

  static const back = SvgIcon(['M15 5l-7 7 7 7']);
  static const forward = SvgIcon(['M9 5l7 7-7 7']);

  /// Dropdown caret. The design writes this as the character "▾", which Figtree
  /// has no glyph for — drawn as a path so it renders everywhere.
  static const caretDown = SvgIcon(['M6 9.5l6 6 6-6'], strokeWidth: 2.2);

  /// Empty attachment slot: a framed picture with a sun and a hill.
  static const imagePlaceholder = SvgIcon(
    [
      'M4 6.5A1.5 1.5 0 0 1 5.5 5h13A1.5 1.5 0 0 1 20 6.5v11A1.5 1.5 0 0 1 18.5 19h-13A1.5 1.5 0 0 1 4 17.5z',
      'M4 15l4.5-4.5 4 4 2.5-2.5L20 16',
    ],
    circles: [SvgCircle(9, 9, 1.4)],
    strokeWidth: 1.6,
  );
  static const close = SvgIcon(['M6 6l12 12M18 6L6 18']);
  static const plus = SvgIcon(['M12 5v14M5 12h14']);
  static const arrowDown = SvgIcon(['M12 4v16M6 14l6 6 6-6']);
  static const check = SvgIcon(['M5 12.5l4.5 4.5L19 7.5'], strokeWidth: 2.3);

  static const search = SvgIcon(
    ['M16 16l4 4'],
    circles: [SvgCircle(11, 11, 6.5)],
  );

  static const searchPlus = SvgIcon(
    ['M16 16l4 4M11 8.5v5M8.5 11h5'],
    circles: [SvgCircle(11, 11, 6.5)],
  );

  static const settings = SvgIcon(
    [
      'M12 2.6l1.1.02.35 2.05a7.4 7.4 0 0 1 1.86.78l1.7-1.2 1.6 1.6-1.2 1.7c.33.57.6 1.2.78 1.86l2.05.35v2.26l-2.05.35a7.4 7.4 0 0 1-.78 1.86l1.2 1.7-1.6 1.6-1.7-1.2c-.58.33-1.2.6-1.86.78l-.35 2.05h-2.26l-.35-2.05a7.4 7.4 0 0 1-1.86-.78l-1.7 1.2-1.6-1.6 1.2-1.7a7.4 7.4 0 0 1-.78-1.86l-2.05-.35v-2.26l2.05-.35c.18-.66.45-1.29.78-1.86l-1.2-1.7 1.6-1.6 1.7 1.2c.57-.33 1.2-.6 1.86-.78l.35-2.05z',
    ],
    circles: [SvgCircle(12, 12, 3.1)],
    strokeWidth: 1.7,
  );

  static const camera = SvgIcon(
    [
      'M3 8.5A2.5 2.5 0 0 1 5.5 6h2.2l1-2h4.6l1 2h3.2A2.5 2.5 0 0 1 20 8.5v8A2.5 2.5 0 0 1 17.5 19h-12A2.5 2.5 0 0 1 3 16.5z',
    ],
    circles: [SvgCircle(11.5, 12.8, 3.2)],
    strokeWidth: 1.9,
  );

  static const document = SvgIcon(
    ['M6 3.5h8l4 4v13H6z', 'M14 3.5v4h4M9 12h6M9 15.5h4'],
    strokeWidth: 1.9,
  );

  static const calendar = SvgIcon(
    [
      'M4 7.5A1.5 1.5 0 0 1 5.5 6h13A1.5 1.5 0 0 1 20 7.5v11A1.5 1.5 0 0 1 18.5 20h-13A1.5 1.5 0 0 1 4 18.5z',
      'M8 4v4M16 4v4M4 11h16',
    ],
    strokeWidth: 1.8,
  );

  static const attachment = SvgIcon(
    [
      'M20 12.5l-7.8 7.8a4 4 0 0 1-5.7-5.7l8.5-8.5a2.6 2.6 0 0 1 3.7 3.7l-8.5 8.5a1.2 1.2 0 0 1-1.7-1.7l7.8-7.8',
    ],
  );

  static const share = SvgIcon(
    ['M4 13.5v5A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5v-5', 'M12 15V4M8 8l4-4 4 4'],
    strokeWidth: 1.9,
  );

  static const upload = SvgIcon(
    ['M12 16V4M8 8l4-4 4 4', 'M4 14v4.5A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5V14'],
  );

  static const download = SvgIcon(
    ['M12 4v12M8 12l4 4 4-4', 'M4 20h16'],
    strokeWidth: 1.9,
  );

  static const edit = SvgIcon(
    ['M4 20h4l10-10-4-4L4 16z', 'M14.5 5.5l4 4'],
    strokeWidth: 1.9,
  );

  static const editSimple = SvgIcon(['M4 20h4l10-10-4-4L4 16z'], strokeWidth: 1.9);

  static const trash = SvgIcon(
    ['M5 7h14M9 7V4.5h6V7M7 7l1 13h8l1-13'],
    strokeWidth: 1.9,
  );

  static const trashLines = SvgIcon(['M5 7h14M9 7V4.5h6V7M7 7l1 13h8l1-13M11 11v5M13 11v5']);

  static const filter = SvgIcon(['M4 7h16M7 12h10M10 17h4']);

  static const crop = SvgIcon(['M7 3v14h14', 'M17 21V7H3'], strokeWidth: 1.9);

  static const rotate = SvgIcon(
    ['M20 11a8 8 0 1 0-2.5 5.8', 'M20 4v7h-7'],
    strokeWidth: 1.9,
  );

  static const info = SvgIcon(
    ['M12 16v-4.5M12 8h.01'],
    circles: [SvgCircle(12, 12, 8.5)],
  );

  static const errorCircle = SvgIcon(
    ['M12 8v4.5M12 16h.01'],
    circles: [SvgCircle(12, 12, 8.5)],
  );

  static const warningTriangle = SvgIcon(
    ['M12 4.5l8.5 15h-17z', 'M12 10v4M12 16.5h.01'],
    strokeWidth: 1.9,
  );

  static const logout = SvgIcon(
    [
      'M14 8V6a1.5 1.5 0 0 0-1.5-1.5h-7A1.5 1.5 0 0 0 4 6v12a1.5 1.5 0 0 0 1.5 1.5h7A1.5 1.5 0 0 0 14 18v-2',
      'M9 12h11M17 9l3 3-3 3',
    ],
  );

  static const dragHandle = SvgIcon(['M8 8h8M8 12h8M8 16h8']);

  static const trendUp = SvgIcon(['M5 16l5-6 4 3 5-7'], strokeWidth: 2.2);

  // ── AI (prompt 02) — not in the design file; drawn to match the set ─────

  /// Four-point spark with a small companion — every AI entry point.
  static const sparkle = SvgIcon(
    [
      'M12 3.5l1.9 5.6 5.6 1.9-5.6 1.9L12 18.5l-1.9-5.6-5.6-1.9 5.6-1.9z',
      'M19 15.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z',
    ],
    strokeWidth: 1.8,
  );

  /// A key on a ring — the API keys list.
  static const key = SvgIcon(
    ['M10.5 13.5L19.5 4.5', 'M16 8l2.5 2.5', 'M13.5 10.5l2 2'],
    circles: [SvgCircle(7.5, 16.5, 3.5)],
    strokeWidth: 1.9,
  );

  static const print = SvgIcon(
    [
      'M7 9V4h10v5',
      'M5 9h14a1.5 1.5 0 0 1 1.5 1.5v5H17v-2H7v2H3.5v-5A1.5 1.5 0 0 1 5 9z',
      'M7 15h10v5H7z',
    ],
    strokeWidth: 1.8,
  );

  // ── Notification capture (prompt 03) ─────────────────────────────────────

  /// A bell — Notices and Notification capture.
  static const bell = SvgIcon(
    [
      'M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z',
      'M10 20a2 2 0 0 0 4 0',
    ],
    strokeWidth: 1.9,
  );

  // ── Bottom navigation ────────────────────────────────────────────────────
  static const navHome =
      SvgIcon(['M4 11l8-6.5 8 6.5v8a1.5 1.5 0 0 1-1.5 1.5H15v-6H9v6H5.5A1.5 1.5 0 0 1 4 19z']);
  static const navTimeline = SvgIcon(['M4 6.5h16M4 12h16M4 17.5h10']);

  /// Three rising bars — the Performance tab. Not in the design file (it
  /// gates the tab off), drawn to match the weight of its siblings.
  static const navPerformance = SvgIcon(['M5 19v-6M12 19V5M19 19v-9']);
  static const navMore = SvgIcon(['M5 12h.01M12 12h.01M19 12h.01']);
}
