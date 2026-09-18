import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../errors/app_failure.dart';
import '../theme/app_tokens.dart';

/// One file the parent has chosen but not yet saved.
///
/// Deliberately not an [Attachment]: it has no id, no Storage path and no
/// record to belong to until the form is saved.
class PickedAttachment {
  const PickedAttachment({
    required this.path,
    required this.name,
    required this.bytes,
    required this.isPdf,
    this.mimeType,
  });

  final String path;
  final String name;
  final int bytes;
  final bool isPdf;
  final String? mimeType;

  File get file => File(path);
}

/// Camera, gallery, file picking, cropping and compression (§12, §23).
///
/// The compression target is chosen for *legibility, not photography*: a
/// worksheet is only useful if the handwriting on it can still be read, so the
/// long edge is capped generously at 2000px rather than squeezed to a
/// thumbnail.
abstract final class ImageService {
  static final ImagePicker _picker = ImagePicker();

  /// Roughly A4 at 170dpi — small enough to upload on mobile data, large
  /// enough that pencil on ruled paper stays readable when zoomed.
  static const int maxDimension = 2000;
  static const int quality = 82;

  /// Below this, re-encoding costs more quality than it saves bytes.
  static const int compressAboveBytes = 400 * 1024;

  /// §31/§32: refuse oversized files before they reach Storage.
  static const int maxFileBytes = 25 * 1024 * 1024;

  static const Set<String> allowedExtensions = {'jpg', 'jpeg', 'png', 'pdf'};

  /// Where a picked file's working copy lives from the moment it is picked
  /// until it is either uploaded or discarded.
  ///
  /// Deliberately not [getTemporaryDirectory]: that directory is the OS's to
  /// reclaim under storage pressure, and a worksheet photographed with no
  /// signal (§25, §32) can sit staged for a while before the upload queue
  /// gets a connection to drain it. A file the OS is free to delete out from
  /// under a still-pending upload is exactly what leaves a saved record with
  /// no local copy and no download URL — permanently unable to show a
  /// preview anywhere it is browsed.
  static Future<Directory> _stagingDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/staged_attachments');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Captures one photo. Returns null when the parent backs out.
  static Future<PickedAttachment?> capture() async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        // Let the platform downscale first; [_process] does the fine work.
        maxWidth: maxDimension.toDouble(),
        maxHeight: maxDimension.toDouble(),
        imageQuality: 95,
      );
      if (shot == null) return null;
      return _process(shot.path, shot.name);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Gallery selection. §10 requires multi-select.
  static Future<List<PickedAttachment>> pickFromGallery({
    bool multiple = true,
  }) async {
    try {
      if (!multiple) {
        final one = await _picker.pickImage(source: ImageSource.gallery);
        if (one == null) return const [];
        final processed = await _process(one.path, one.name);
        return processed == null ? const [] : [processed];
      }
      final shots = await _picker.pickMultiImage();
      final out = <PickedAttachment>[];
      for (final shot in shots) {
        final processed = await _process(shot.path, shot.name);
        if (processed != null) out.add(processed);
      }
      return out;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Files app / document picker, limited to the formats §23 supports.
  static Future<List<PickedAttachment>> pickFiles({
    bool multiple = true,
  }) async {
    try {
      final picks = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions.toList(),
      );
      if (picks.isEmpty) return const [];
      final selected = multiple ? picks : picks.take(1);

      final out = <PickedAttachment>[];
      for (final picked in selected) {
        final path = picked.path;
        if (path == null) continue;
        final ext = _extensionOf(picked.name);
        if (!allowedExtensions.contains(ext)) {
          throw const AppFailure(
            FailureKind.invalidFile,
            'Only JPG, PNG and PDF files can be attached.',
            canRetry: false,
          );
        }
        if (ext == 'pdf') {
          final size = await File(path).length();
          _guardSize(size);

          final targetFolder = await _stagingDir();
          final safeName =
              '${DateTime.now().millisecondsSinceEpoch}_${picked.name}';
          final localCopy = File('${targetFolder.path}/$safeName');
          await File(path).copy(localCopy.path);

          out.add(
            PickedAttachment(
              path: localCopy.path,
              name: picked.name,
              bytes: size,
              isPdf: true,
              mimeType: 'application/pdf',
            ),
          );
        } else {
          final processed = await _process(path, picked.name);
          if (processed != null) out.add(processed);
        }
      }
      return out;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Opens the platform cropper. Returns the original when the parent cancels,
  /// so "Crop" is never a way to lose a photo.
  static Future<PickedAttachment> crop(
    PickedAttachment source, {
    required AppTokens tokens,
  }) async {
    if (source.isPdf) return source;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: source.path,
        maxWidth: maxDimension,
        maxHeight: maxDimension,
        compressQuality: quality,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop',
            toolbarColor: tokens.bg,
            toolbarWidgetColor: tokens.tx,
            backgroundColor: tokens.bg,
            activeControlsWidgetColor: tokens.pri,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(title: 'Crop', aspectRatioLockEnabled: false),
        ],
      );
      if (cropped == null) return source;
      final size = await File(cropped.path).length();
      return PickedAttachment(
        path: await _persist(cropped.path, source.name),
        name: source.name,
        bytes: size,
        isPdf: false,
        mimeType: source.mimeType,
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Rotates by 90°, re-encoding in place. The cropper owns free rotation; this
  /// is the one-tap version the capture screen's toolbar offers.
  static Future<PickedAttachment> rotate(PickedAttachment source) async {
    if (source.isPdf) return source;
    try {
      final target = await _tempPath(source.name, suffix: 'rot');
      final out = await FlutterImageCompress.compressAndGetFile(
        source.path,
        target,
        quality: quality,
        rotate: 90,
      );
      if (out == null) return source;
      return PickedAttachment(
        path: out.path,
        name: source.name,
        bytes: await File(out.path).length(),
        isPdf: false,
        mimeType: source.mimeType,
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// A copy sized for a model, not a parent: 1600px long edge, quality 75,
  /// always JPEG. The re-encode also drops EXIF (location, device), which
  /// is the one piece of metadata that must never leave the phone. Never
  /// sends the Storage original.
  static Future<String> compressForAi(String path) async {
    const aiDimension = 1600;
    const aiQuality = 75;
    try {
      final target = await _tempPath('ai_${path.split('/').last}', suffix: 'ai');
      final out = await FlutterImageCompress.compressAndGetFile(
        path,
        target,
        quality: aiQuality,
        minWidth: aiDimension,
        minHeight: aiDimension,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      return out?.path ?? path;
    } catch (_) {
      return path;
    }
  }

  /// Writes bytes the app produced itself (a rendered PDF) into the staging
  /// directory so they can be attached like any picked file.
  static Future<PickedAttachment> stageBytes(
    List<int> bytes,
    String name, {
    String mimeType = 'application/pdf',
  }) async {
    final dir = await _stagingDir();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}/${stamp}_$name');
    await file.writeAsBytes(bytes, flush: true);
    return PickedAttachment(
      path: file.path,
      name: name,
      bytes: bytes.length,
      isPdf: mimeType == 'application/pdf',
      mimeType: mimeType,
    );
  }

  /// Entry point for the share sheet, which hands over a path the app did not
  /// pick. Same validation and compression as every other source.
  static Future<PickedAttachment?> compressShared(String path, String name) =>
      _process(path, name);

  // ── internals ───────────────────────────────────────────────────────────

  /// Validates, then compresses when it is worth doing.
  static Future<PickedAttachment?> _process(String path, String name) async {
    final source = File(path);
    if (!await source.exists()) return null;

    final original = await source.length();
    _guardSize(original);

    final ext = _extensionOf(name);
    if (!allowedExtensions.contains(ext)) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'Only JPG, PNG and PDF files can be attached.',
        canRetry: false,
      );
    }

    if (original <= compressAboveBytes) {
      return PickedAttachment(
        path: await _persist(path, name),
        name: name,
        bytes: original,
        isPdf: false,
        mimeType: _mimeFor(ext),
      );
    }

    try {
      final target = await _tempPath(name);
      final out = await FlutterImageCompress.compressAndGetFile(
        path,
        target,
        quality: quality,
        minWidth: maxDimension,
        minHeight: maxDimension,
        // PNG screenshots of worksheets are common and compress far better as
        // JPEG; transparency is meaningless for a photographed page.
        format: CompressFormat.jpeg,
      );
      if (out == null) {
        return PickedAttachment(
          path: await _persist(path, name),
          name: name,
          bytes: original,
          isPdf: false,
          mimeType: _mimeFor(ext),
        );
      }
      final compressed = await File(out.path).length();
      // Never keep a "compressed" file that came out bigger.
      if (compressed >= original) {
        return PickedAttachment(
          path: await _persist(path, name),
          name: name,
          bytes: original,
          isPdf: false,
          mimeType: _mimeFor(ext),
        );
      }
      return PickedAttachment(
        path: out.path,
        name: _asJpeg(name),
        bytes: compressed,
        isPdf: false,
        mimeType: 'image/jpeg',
      );
    } catch (_) {
      // Compression is an optimisation. If the codec refuses a file, upload the
      // original rather than dropping the parent's photo.
      return PickedAttachment(
        path: await _persist(path, name),
        name: name,
        bytes: original,
        isPdf: false,
        mimeType: _mimeFor(ext),
      );
    }
  }

  /// Copies a file the plugin (image_picker, image_cropper, file_picker) left
  /// in its own volatile cache into [_stagingDir], so the working copy
  /// survives independently of whatever that plugin does with its temp file
  /// next.
  static Future<String> _persist(String path, String name) async {
    final dir = await _stagingDir();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final target = File('${dir.path}/${stamp}_$name');
    await File(path).copy(target.path);
    return target.path;
  }

  static void _guardSize(int bytes) {
    if (bytes > maxFileBytes) {
      throw const AppFailure(
        FailureKind.fileTooLarge,
        'That file is larger than 25 MB. Try a photo instead of a scan.',
        canRetry: false,
      );
    }
  }

  static Future<String> _tempPath(String name, {String suffix = 'cmp'}) async {
    final dir = await _stagingDir();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/${stamp}_$suffix${_asJpeg(name)}';
  }

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static String _asJpeg(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot == -1 ? name : name.substring(0, dot);
    return '$stem.jpg';
  }

  static String _mimeFor(String extension) => switch (extension) {
    'png' => 'image/png',
    'pdf' => 'application/pdf',
    _ => 'image/jpeg',
  };

  /// "240 KB" / "1.4 MB" — the caption the design shows under a file.
  static String humanSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}
