import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Resolves an [Attachment] to something [Image] can draw.
///
/// Prefers the on-device copy: it is already the compressed file that was
/// uploaded, it renders with no network round trip, and it is what makes a
/// just-captured worksheet appear instantly on a phone with no signal. Falls
/// back to the Storage URL for records that arrived from another device.
ImageProvider? attachmentImage(Attachment? attachment) {
  if (attachment == null || attachment.isPdf) return null;

  final localPath = attachment.localPath;
  if (localPath != null && localPath.isNotEmpty) {
    final file = File(localPath);
    // Synchronous on purpose — this runs in build, and an existsSync on a path
    // the app just wrote is a stat call, not I/O worth an await.
    if (file.existsSync()) return FileImage(file);
  }

  final url = attachment.downloadUrl;
  if (url != null && url.isNotEmpty) return NetworkImage(url);

  return null;
}

/// The same for a file the parent has picked but not yet saved.
ImageProvider? fileImage(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}
