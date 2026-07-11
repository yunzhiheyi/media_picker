import 'dart:typed_data';

import 'media_type.dart';

/// A single asset returned by [MediaPicker].
class PickedMedia {
  final MediaKind kind;

  /// Absolute local file path (exported from album when needed).
  final String path;

  /// Optional display name.
  final String? name;

  /// Byte size when known.
  final int? size;

  /// Pixel size when known (images / videos).
  final int? width;
  final int? height;

  /// Video duration when kind is [MediaKind.video].
  final Duration? duration;

  /// Lightweight preview bytes (thumbnail) when available.
  final Uint8List? thumbnailBytes;

  /// Album asset id when picked from photo library.
  final String? assetId;

  const PickedMedia({
    required this.kind,
    required this.path,
    this.name,
    this.size,
    this.width,
    this.height,
    this.duration,
    this.thumbnailBytes,
    this.assetId,
  });
}
