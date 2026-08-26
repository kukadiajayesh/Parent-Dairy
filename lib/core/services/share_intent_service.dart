import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'image_service.dart';
import 'telemetry_service.dart';

/// Receives images and PDFs shared into the app from WhatsApp, Gallery, Google
/// Photos or a file manager (§11, §38).
///
/// This is the feature the spec calls core, and the one the design's "Create
/// Academic Record" screen exists for: a parent gets a worksheet photo on
/// WhatsApp and files it without ever opening the app first.
class ShareIntentService {
  ShareIntentService({ReceiveSharingIntent? intent})
    : _intent = intent ?? ReceiveSharingIntent.instance;

  final ReceiveSharingIntent _intent;
  StreamSubscription<List<SharedMediaFile>>? _sub;

  /// Files waiting to be turned into a record. The app shell watches this and
  /// pushes the quick-add screen when it fills.
  final ValueNotifier<List<PickedAttachment>> incoming =
      ValueNotifier<List<PickedAttachment>>(const []);

  /// Starts listening. Handles both entry points: a share that launched the app
  /// cold, and one that arrived while it was already running.
  Future<void> start() async {
    _sub = _intent.getMediaStream().listen(
      _accept,
      onError: (Object error, StackTrace stack) => unawaited(
        Telemetry.recordError(error, stack, context: 'shareIntentStream'),
      ),
    );

    try {
      final initial = await _intent.getInitialMedia();
      if (initial.isNotEmpty) {
        await _accept(initial);
        // Tells the platform the launch payload is consumed, so a later resume
        // does not replay the same share.
        await _intent.reset();
      }
    } catch (error, stack) {
      unawaited(
        Telemetry.recordError(error, stack, context: 'shareIntentInitial'),
      );
    }
  }

  Future<void> _accept(List<SharedMediaFile> shared) async {
    final usable = <PickedAttachment>[];

    for (final item in shared) {
      // Text and URL shares have no file to attach; a video is not an academic
      // document. Both are ignored rather than failing the whole share.
      if (item.type != SharedMediaType.image &&
          item.type != SharedMediaType.file) {
        continue;
      }

      final file = File(item.path);
      if (!await file.exists()) continue;

      final name = item.path.split(Platform.pathSeparator).last;
      final isPdf =
          (item.mimeType ?? '').contains('pdf') ||
          name.toLowerCase().endsWith('.pdf');

      try {
        final size = await file.length();
        if (size > ImageService.maxFileBytes) continue;

        if (isPdf) {
          final tempDir = await getTemporaryDirectory();
          final targetFolder = Directory('${tempDir.path}/attachments');
          if (!await targetFolder.exists()) {
            await targetFolder.create(recursive: true);
          }
          final safeName = '${DateTime.now().millisecondsSinceEpoch}_$name';
          final localCopy = File('${targetFolder.path}/$safeName');
          await file.copy(localCopy.path);

          usable.add(
            PickedAttachment(
              path: localCopy.path,
              name: name,
              bytes: size,
              isPdf: true,
              mimeType: 'application/pdf',
            ),
          );
          continue;
        }

        // Route images through the same compression the camera path uses, so a
        // 6 MB WhatsApp forward does not become a 6 MB upload.
        final processed = await ImageService.compressShared(item.path, name);
        if (processed != null) usable.add(processed);
      } catch (error, stack) {
        unawaited(
          Telemetry.recordError(error, stack, context: 'shareIntentAccept'),
        );
      }
    }

    if (usable.isEmpty) return;
    unawaited(Telemetry.imageSharedToApp(usable.length));
    incoming.value = usable;
  }

  /// Called once the quick-add screen has taken the files.
  void consume() {
    if (incoming.value.isEmpty) return;
    incoming.value = const [];
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    incoming.dispose();
  }
}
