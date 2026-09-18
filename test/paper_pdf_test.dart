import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/ai/paper_pdf.dart';
import 'package:parent_academic_diary/data/models_ai.dart';

Future<Map<String, Object?>> fixture(String name) async =>
    Map<String, Object?>.from(jsonDecode(await File('test/fixtures/ai/$name').readAsString()) as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a generated paper renders to two page groups with the Figtree font', () async {
    final fonts = await PaperFonts.load();
    final paper = GeneratedPaper.fromJson(await fixture('paper_clean.json'));

    final withKey = PaperPdf.buildPaper(paper, fonts: fonts, includeAnswerKey: true);
    final bytesWithKey = await withKey.save();
    expect(bytesWithKey, isNotEmpty);
    expect(withKey.document.pdfPageList.pages.length, greaterThanOrEqualTo(2));

    final withoutKey = PaperPdf.buildPaper(paper, fonts: fonts, includeAnswerKey: false);
    await withoutKey.save();
    expect(
      withoutKey.document.pdfPageList.pages.length,
      lessThan(withKey.document.pdfPageList.pages.length),
    );

    final head = latin1.decode(bytesWithKey.take(8).toList());
    expect(head, startsWith('%PDF-'));
    // The embedded font is the app's own, not a Helvetica fallback.
    expect(latin1.decode(bytesWithKey, allowInvalid: true), contains('Figtree'));
  });

  test('a scanned paper and its answer key render to a non-empty PDF', () async {
    final fonts = await PaperFonts.load();
    final paper = ScannedPaper.fromJson(await fixture('scanned_paper.json'));
    final key = AnswerKey.fromJson(await fixture('answer_key.json'));
    final doc = PaperPdf.buildAnswerKey(paper, key, fonts: fonts, title: 'Answer key · Unit Test 2');
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
    expect(doc.document.pdfPageList.pages.length, greaterThanOrEqualTo(1));
  });
}
