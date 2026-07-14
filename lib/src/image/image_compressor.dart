import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/compress_options.dart';
import '../models/compress_result.dart';

/// Client-side image re-encode. Re-encoding strips EXIF/GPS by design.
class ImageCompressor {
  ImageCompressor._();

  static Future<ImageCompressResult> compressFile(
    String inputPath, {
    ImageCompressOptions options = const ImageCompressOptions(),
    String? outputPath,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw StateError('Image file not found: $inputPath');
    }
    final originalSize = await input.length();
    final decoded = await _decodeSize(inputPath);
    final target = _fitLongEdge(decoded.$1, decoded.$2, options.maxSide);

    var quality = options.quality;
    Uint8List? bytes;
    while (true) {
      bytes = await FlutterImageCompress.compressWithFile(
        inputPath,
        minWidth: target.$1,
        minHeight: target.$2,
        quality: quality,
        format: _mapFormat(options.format),
        keepExif: false,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Image compress returned empty bytes');
      }
      if (options.maxBytes == null ||
          bytes.length <= options.maxBytes! ||
          quality <= options.minQuality) {
        break;
      }
      quality = (quality - 10).clamp(options.minQuality, options.quality);
    }

    final outPath = outputPath ?? await _tempPath(options.format);
    await File(outPath).writeAsBytes(bytes, flush: true);

    // flutter_image_compress may not return exact dims; re-probe when possible.
    final outSize = await _decodeSize(outPath);

    return ImageCompressResult(
      path: outPath,
      bytes: bytes,
      width: outSize.$1,
      height: outSize.$2,
      size: bytes.length,
      originalSize: originalSize,
    );
  }

  static Future<ImageCompressResult> compressBytes(
    Uint8List input, {
    ImageCompressOptions options = const ImageCompressOptions(),
    String? outputPath,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final inPath = p.join(
      tempDir.path,
      'mc_in_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(inPath).writeAsBytes(input, flush: true);
    try {
      return await compressFile(
        inPath,
        options: options,
        outputPath: outputPath,
      );
    } finally {
      try {
        await File(inPath).delete();
      } catch (_) {}
    }
  }

  static CompressFormat _mapFormat(ImageOutputFormat format) {
    switch (format) {
      case ImageOutputFormat.jpeg:
        return CompressFormat.jpeg;
      case ImageOutputFormat.webp:
        return CompressFormat.webp;
      case ImageOutputFormat.png:
        return CompressFormat.png;
    }
  }

  static (int, int) _fitLongEdge(int w, int h, int maxSide) {
    if (w <= 0 || h <= 0) return (maxSide, maxSide);
    final long = w > h ? w : h;
    if (long <= maxSide) return (w, h);
    final scale = maxSide / long;
    return (
      (w * scale).round().clamp(1, maxSide),
      (h * scale).round().clamp(1, maxSide),
    );
  }

  static Future<(int, int)> _decodeSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      return (w, h);
    } catch (e) {
      debugPrint('[ImageCompressor] decode size failed: $e');
      return (0, 0);
    }
  }

  static Future<String> _tempPath(ImageOutputFormat format) async {
    final dir = await getTemporaryDirectory();
    final ext = switch (format) {
      ImageOutputFormat.jpeg => 'jpg',
      ImageOutputFormat.webp => 'webp',
      ImageOutputFormat.png => 'png',
    };
    return p.join(
      dir.path,
      'mc_img_${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
  }
}
