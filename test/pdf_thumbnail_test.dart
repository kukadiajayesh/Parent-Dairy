import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/pdf_thumbnail_service.dart';
import 'package:parent_academic_diary/data/models.dart';

void main() {
  setUp(() {
    PdfThumbnailService.clearCache();
  });

  group('PdfThumbnailService cacheKey', () {
    test('prefers attachment id when non-empty', () {
      const att = Attachment(
        id: 'att-123',
        name: 'sample.pdf',
        meta: 'Page 1',
        isPdf: true,
        localPath: '/tmp/sample.pdf',
      );
      expect(PdfThumbnailService.cacheKey(att), 'att-123');
    });

    test('falls back to localPath when id is empty', () {
      const att = Attachment(
        name: 'sample.pdf',
        meta: 'Page 1',
        isPdf: true,
        localPath: '/tmp/sample.pdf',
      );
      expect(PdfThumbnailService.cacheKey(att), '/tmp/sample.pdf');
    });

    test('falls back to storagePath or downloadUrl or name when localPath is null', () {
      const attWithStorage = Attachment(
        name: 'sample.pdf',
        meta: 'Page 1',
        isPdf: true,
        storagePath: 'worksheets/sample.pdf',
      );
      expect(
        PdfThumbnailService.cacheKey(attWithStorage),
        'worksheets/sample.pdf',
      );

      const attWithUrl = Attachment(
        name: 'sample.pdf',
        meta: 'Page 1',
        isPdf: true,
        downloadUrl: 'https://example.com/sample.pdf',
      );
      expect(
        PdfThumbnailService.cacheKey(attWithUrl),
        'https://example.com/sample.pdf',
      );

      const attWithName = Attachment(
        name: 'sample.pdf',
        meta: 'Page 1',
        isPdf: true,
      );
      expect(PdfThumbnailService.cacheKey(attWithName), 'sample.pdf');
    });
  });

  group('Attachment isPdf detection', () {
    test('detects PDF from isPdf boolean', () {
      const att = Attachment(name: 'doc', meta: '', isPdf: true);
      expect(att.isPdf, isTrue);
      expect(att.isImage, isFalse);
    });

    test('detects PDF from filename extension even if isPdf is false', () {
      const att = Attachment(name: 'worksheet_chapter1.PDF', meta: '');
      expect(att.isPdf, isTrue);
      expect(att.isImage, isFalse);
    });

    test('detects PDF from mimeType', () {
      const att = Attachment(
        name: 'download',
        meta: '',
        mimeType: 'application/pdf',
      );
      expect(att.isPdf, isTrue);
      expect(att.isImage, isFalse);
    });

    test('treats normal image as non-PDF', () {
      const att = Attachment(name: 'photo.jpg', meta: '');
      expect(att.isPdf, isFalse);
      expect(att.isImage, isTrue);
    });
  });
}
