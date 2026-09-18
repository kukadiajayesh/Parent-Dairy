import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/config/grade_scale.dart';

void main() {
  group('CBSE 9-point', () {
    const scale = GradeScale.cbse9;

    test('every band resolves to its midpoint', () {
      expect(scale.percentFor('A1'), 95.5);
      expect(scale.percentFor('A2'), 85.5);
      expect(scale.percentFor('B1'), 75.5);
      expect(scale.percentFor('B2'), 65.5);
      expect(scale.percentFor('C1'), 55.5);
      expect(scale.percentFor('C2'), 45.5);
      expect(scale.percentFor('D'), 36.5);
      expect(scale.percentFor('E1'), 26.5);
      expect(scale.percentFor('E2'), 10);
    });

    test('bands tile 0–100 without gaps or overlaps', () {
      final bands = scale.bands.values.toList()
        ..sort((a, b) => a.min.compareTo(b.min));
      expect(bands.first.min, 0);
      expect(bands.last.max, 100);
      for (var i = 1; i < bands.length; i++) {
        expect(
          bands[i].min,
          bands[i - 1].max + 1,
          reason: 'band ${i - 1} and $i must be adjacent',
        );
      }
    });

    test('is forgiving about case and whitespace', () {
      expect(scale.percentFor(' a1 '), 95.5);
      expect(scale.percentFor('b2'), 65.5);
    });

    test('an unknown grade is null, never zero', () {
      expect(scale.percentFor('A+'), isNull);
      expect(scale.percentFor(''), isNull);
      expect(scale.percentFor(null), isNull);
    });
  });

  group('five-letter', () {
    test('uses 20-point bands', () {
      expect(GradeScale.fiveLetter.percentFor('A'), 90.5);
      expect(GradeScale.fiveLetter.percentFor('C'), 50.5);
      expect(GradeScale.fiveLetter.percentFor('E'), 10);
      expect(GradeScale.fiveLetter.percentFor('A1'), isNull);
    });
  });

  group('none', () {
    test('never resolves a grade', () {
      expect(GradeScale.none.hasBands, isFalse);
      expect(GradeScale.none.percentFor('A1'), isNull);
    });
  });

  group('byId', () {
    test('finds every shipped scale', () {
      for (final scale in GradeScale.all) {
        expect(GradeScale.byId(scale.id), same(scale));
      }
    });

    test('falls back to CBSE for an unknown or missing id', () {
      expect(GradeScale.byId('icse'), same(GradeScale.cbse9));
      expect(GradeScale.byId(null), same(GradeScale.cbse9));
      expect(GradeScale.defaultId, GradeScale.cbse9.id);
    });
  });
}
