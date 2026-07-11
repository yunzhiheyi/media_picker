import 'dart:typed_data';

import 'video_info.dart';

/// Result of an image compress / thumbnail pass.
class ImageCompressResult {
  final String path;
  final Uint8List bytes;
  final int width;
  final int height;
  final int size;
  final int originalSize;

  const ImageCompressResult({
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
    required this.size,
    required this.originalSize,
  });

  double get compressionRatio =>
      originalSize == 0 ? 1 : size / originalSize;
}

/// Result of a video compress pass.
class VideoCompressResult {
  final String path;
  final int size;
  final int originalSize;
  final VideoInfo? info;

  const VideoCompressResult({
    required this.path,
    required this.size,
    required this.originalSize,
    this.info,
  });

  double get compressionRatio =>
      originalSize == 0 ? 1 : size / originalSize;
}
