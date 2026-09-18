import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/theme/app_theme.dart';
import 'package:parent_academic_diary/core/widgets/attachment_image.dart';
import 'package:parent_academic_diary/core/widgets/image_slot.dart';
import 'package:parent_academic_diary/data/models.dart';

/// Prompt 04 §1.2: a worksheet photo is stored at up to 2000px on the long
/// edge and drawn into a ~88dp slot. Decoded at full size that is 12MB of
/// ARGB per thumbnail in the image cache; decoded at slot size it is a few
/// hundred kilobytes. This pins the second behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File photo;

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 2000, 1500),
      Paint()..color = const Color(0xFF3E8168),
    );
    final image = await recorder.endRecording().toImage(2000, 1500);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    photo = File('${Directory.systemTemp.path}/diary_decode_test.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });

  tearDownAll(() {
    if (photo.existsSync()) photo.deleteSync();
  });

  setUp(() {
    imageCache.clear();
    imageCache.clearLiveImages();
    clearKnownFilesCache();
  });

  Future<void> pumpSlot(WidgetTester tester, {double? width, double? height}) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(
          child: Builder(
            builder: (context) => attachmentThumb(
              context,
              Attachment(
                id: 'a',
                name: 'page-1.png',
                meta: 'Page 1',
                localPath: photo.path,
                sync: SyncState.synced,
              ),
              width: width,
              height: height,
              showCaption: false,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('an 88×92dp slot decodes the photo at slot size', (tester) async {
    await tester.runAsync(() async {
      await pumpSlot(tester, width: 88, height: 92);
      await tester.pump();
      // Let the file read and decode complete off the fake clock.
      for (var i = 0; i < 20 && imageCache.currentSizeBytes == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    final resize = image.image as ResizeImage;
    // 92dp × 2.625 = 242px, scaled by the slot's 92/88 aspect ratio.
    expect(resize.height, lessThanOrEqualTo(260));
    expect(resize.width, lessThanOrEqualTo(260));
    expect(resize.policy, ResizeImagePolicy.fit);

    final bytes = imageCache.currentSizeBytes;
    expect(bytes, greaterThan(0), reason: 'the image never decoded');
    expect(
      bytes,
      lessThan(1024 * 1024),
      reason: 'decoded ${bytes ~/ 1024}KB for an 88dp thumbnail; a full '
          '2000×1500 decode would be ${2000 * 1500 * 4 ~/ 1024}KB',
    );
  });

  testWidgets('a full-width 280dp slot still decodes well under full size', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await pumpSlot(tester, height: 280);
      await tester.pump();
      for (var i = 0; i < 20 && imageCache.currentSizeBytes == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    final bytes = imageCache.currentSizeBytes;
    expect(bytes, greaterThan(0));
    // A cover crop cannot know the photo's aspect before decoding, so the
    // bound over-decodes by up to the slot's aspect ratio squared — for a
    // 1080×735px hero that is ~7.5MB against 12MB for the full file.
    expect(bytes, lessThan(8 * 1024 * 1024));
  });

  testWidgets('a picked file thumbnail goes through the same path', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Center(
          child: ImageSlot(image: fileImage(photo.path), width: 52, height: 52),
        ),
      ),
    );
    expect(tester.widget<Image>(find.byType(Image)).image, isA<ResizeImage>());
  });
}
