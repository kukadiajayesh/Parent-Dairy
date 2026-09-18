import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/ai/subject_matcher.dart';

void main() {
  const known = ['Mathematics', 'English', 'Science', 'Hindi', 'Social Science', 'Environmental Studies'];

  test('exact and case-insensitive matches', () {
    expect(SubjectMatcher.match('Mathematics', known), 'Mathematics');
    expect(SubjectMatcher.match('english', known), 'English');
    expect(SubjectMatcher.match('  HINDI ', known), 'Hindi');
  });

  test('common report-card shorthands', () {
    expect(SubjectMatcher.match('Maths', known), 'Mathematics');
    expect(SubjectMatcher.match('Math', known), 'Mathematics');
    expect(SubjectMatcher.match('EVS', known), 'Environmental Studies');
    expect(SubjectMatcher.match('E.V.S.', known), 'Environmental Studies');
    expect(SubjectMatcher.match('SST', known), 'Social Science');
    expect(SubjectMatcher.match('Sci', known), 'Science');
    expect(SubjectMatcher.match('Eng', known), 'English');
  });

  test('typos within two edits, prefixes, and nothing for the unknown', () {
    expect(SubjectMatcher.match('Sceince', known), 'Science');
    expect(SubjectMatcher.match('Mathematic', known), 'Mathematics');
    expect(SubjectMatcher.match('Sanskrit', known), isNull);
    expect(SubjectMatcher.match('', known), isNull);
    expect(SubjectMatcher.match('Art & Craft', known), isNull);
  });
}
