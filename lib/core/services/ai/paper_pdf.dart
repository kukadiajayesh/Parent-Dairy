import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../data/models_ai.dart';

/// Figtree, loaded once from the bundled assets so the PDF matches the app
/// and no font is fetched at runtime.
class PaperFonts {
  const PaperFonts({required this.regular, required this.semiBold, required this.bold});

  final pw.Font regular;
  final pw.Font semiBold;
  final pw.Font bold;

  static PaperFonts? _cached;

  static Future<PaperFonts> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    Future<pw.Font> font(String file) async =>
        pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
    return _cached = PaperFonts(
      regular: await font('Figtree-Regular.ttf'),
      semiBold: await font('Figtree-SemiBold.ttf'),
      bold: await font('Figtree-Bold.ttf'),
    );
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(
    base: regular,
    bold: bold,
    italic: regular,
    boldItalic: bold,
  );
}

/// Renders a [GeneratedPaper] or an [AnswerKey] to A4.
///
/// Figtree has Latin glyphs only. A Hindi or Gujarati paper renders its
/// Latin parts and shows the rest as boxes — noted in the summary as a
/// follow-up (bundle Noto Devanagari/Gujarati), not silently dropped.
abstract final class PaperPdf {
  static const String aiBanner =
      'AI-generated — check the questions before your child sits down with them.';

  static pw.Document buildPaper(
    GeneratedPaper paper, {
    required PaperFonts fonts,
    bool includeAnswerKey = true,
  }) {
    final doc = pw.Document(
      title: paper.title,
      author: 'Parent Academic Diary',
      theme: fonts.theme,
    );

    final body = <pw.Widget>[
      _header(paper, fonts),
      pw.SizedBox(height: 6),
      _banner(aiBanner, fonts),
      if (paper.instructions.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text('Instructions', style: pw.TextStyle(font: fonts.bold, fontSize: 11)),
        for (final line in paper.instructions)
          pw.Bullet(text: line, style: const pw.TextStyle(fontSize: 10)),
      ],
      for (final section in paper.sections) ...[
        pw.SizedBox(height: 14),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(section.name, style: pw.TextStyle(font: fonts.bold, fontSize: 12.5)),
            pw.Text('${section.marks} marks', style: pw.TextStyle(font: fonts.semiBold, fontSize: 10)),
          ],
        ),
        if (section.instructions.isNotEmpty)
          pw.Text(section.instructions, style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 4),
        for (final q in section.questions) _question(q, fonts),
        if (section.droppedQuestions > 0)
          pw.Text(
            '(${section.droppedQuestions} question(s) could not be generated)',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
      ],
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
        footer: (ctx) => _footer(ctx, paper.title, fonts),
        build: (_) => body,
      ),
    );

    if (includeAnswerKey) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
          footer: (ctx) => _footer(ctx, '${paper.title} — answer key', fonts),
          build: (_) => [
            pw.Text('Answer key', style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
            pw.Text(paper.title, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.SizedBox(height: 6),
            _banner('AI-generated · verify before use', fonts),
            pw.SizedBox(height: 10),
            for (final q in paper.questions)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(text: '${q.number}. ', style: pw.TextStyle(font: fonts.bold, fontSize: 10)),
                      pw.TextSpan(text: q.answer, style: const pw.TextStyle(fontSize: 10)),
                      if (q.explanation.isNotEmpty)
                        pw.TextSpan(
                          text: '  — ${q.explanation}',
                          style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return doc;
  }

  static pw.Document buildAnswerKey(
    ScannedPaper paper,
    AnswerKey key, {
    required PaperFonts fonts,
    String title = 'Answer key',
  }) {
    final doc = pw.Document(title: title, author: 'Parent Academic Diary', theme: fonts.theme);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 36),
        footer: (ctx) => _footer(ctx, title, fonts),
        build: (_) => [
          pw.Text(title, style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
          pw.Text(
            [
              if (paper.detected.subject.isNotEmpty) paper.detected.subject,
              if (paper.detected.examType.isNotEmpty) paper.detected.examType,
              if (paper.detected.grade.isNotEmpty) paper.detected.grade,
            ].join(' · '),
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 6),
          _banner('AI-generated · verify before use', fonts),
          pw.SizedBox(height: 10),
          for (final q in paper.questions) ...[
            pw.Text('${q.number}. ${q.text}', style: pw.TextStyle(font: fonts.semiBold, fontSize: 10)),
            for (final a in [?key.forNumber(q.number)]) ...[
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Answer: ${a.answer}', style: const pw.TextStyle(fontSize: 10)),
                    for (var i = 0; i < a.workedSolution.length; i++)
                      pw.Text(
                        '${i + 1}. ${a.workedSolution[i]}',
                        style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey800),
                      ),
                    if (a.markingScheme.isNotEmpty)
                      pw.Text(
                        'Marking: ${a.markingScheme.map((m) => '${_trim(m.points)} for ${m.reason}').join('; ')}',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    if (a.commonMistakes.isNotEmpty)
                      pw.Text(
                        'Watch for: ${a.commonMistakes.join('; ')}',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                  ],
                ),
              ),
            ],
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    );
    return doc;
  }

  static Future<Uint8List> renderPaper(
    GeneratedPaper paper, {
    required PaperFonts fonts,
    bool includeAnswerKey = true,
  }) => buildPaper(paper, fonts: fonts, includeAnswerKey: includeAnswerKey).save();

  static Future<Uint8List> renderAnswerKey(
    ScannedPaper paper,
    AnswerKey key, {
    required PaperFonts fonts,
    String title = 'Answer key',
  }) => buildAnswerKey(paper, key, fonts: fonts, title: title).save();

  // ── pieces ──────────────────────────────────────────────────────────────

  static pw.Widget _header(GeneratedPaper paper, PaperFonts fonts) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(paper.title, style: pw.TextStyle(font: fonts.bold, fontSize: 17)),
      pw.SizedBox(height: 3),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            [paper.grade, paper.subject].where((s) => s.isNotEmpty).join(' · '),
            style: pw.TextStyle(fontSize: 10.5, color: PdfColors.grey800),
          ),
          pw.Text(
            'Time: ${paper.durationMinutes} min   Max marks: ${paper.totalMarks}',
            style: pw.TextStyle(font: fonts.semiBold, fontSize: 10.5),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          pw.Text('Name: ', style: pw.TextStyle(font: fonts.semiBold, fontSize: 10)),
          pw.Expanded(child: pw.Divider(thickness: .6, color: PdfColors.grey500)),
          pw.SizedBox(width: 14),
          pw.Text('Date: ', style: pw.TextStyle(font: fonts.semiBold, fontSize: 10)),
          pw.SizedBox(width: 90, child: pw.Divider(thickness: .6, color: PdfColors.grey500)),
        ],
      ),
    ],
  );

  static pw.Widget _banner(String text, PaperFonts fonts) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: PdfColors.grey200,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(text, style: pw.TextStyle(font: fonts.semiBold, fontSize: 8.5, color: PdfColors.grey800)),
  );

  static pw.Widget _question(PaperQuestion q, PaperFonts fonts) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 7),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 24,
              child: pw.Text('${q.number}.', style: pw.TextStyle(font: fonts.semiBold, fontSize: 10.5)),
            ),
            pw.Expanded(child: pw.Text(q.text, style: const pw.TextStyle(fontSize: 10.5))),
            pw.SizedBox(width: 8),
            pw.Text('[${q.marks}]', style: pw.TextStyle(fontSize: 9.5, color: PdfColors.grey700)),
          ],
        ),
        if (q.options.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 24, top: 2),
            child: pw.Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (var i = 0; i < q.options.length; i++)
                  pw.Text(
                    '(${String.fromCharCode(97 + i)}) ${q.options[i]}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
              ],
            ),
          ),
        if (q.type == QuestionType.long)
          pw.SizedBox(height: 54)
        else if (q.type == QuestionType.short || q.type == QuestionType.match)
          pw.SizedBox(height: 22),
      ],
    ),
  );

  static pw.Widget _footer(pw.Context ctx, String title, PaperFonts fonts) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(title, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      pw.Text(
        'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
      ),
    ],
  );

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
