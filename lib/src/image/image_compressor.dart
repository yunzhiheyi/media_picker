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
    void Function(double progress)? onProgress,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw StateError('Image file not found: $inputPath');
    }
    onProgress?.call(0.02);
    final originalSize = await input.length();
    final decoded = await _decodeSize(inputPath);
    final target = _fitLongEdge(decoded.$1, decoded.$2, options.maxSide);
    onProgress?.call(0.1);

    var quality = options.quality;
    Uint8List? bytes;
    var pass = 0;
    while (true) {
      // flutter_image_compress has no native progress callback. We expose its
      // deterministic phases (decode -> native encode pass -> file write)
      // without pretending the encoder itself reports byte-level progress.
      onProgress?.call((0.12 + pass * 0.16).clamp(0.12, 0.72));
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
      pass++;
    }

    final outPath = outputPath ?? await _tempPath(options.format);
    await File(outPath).writeAsBytes(bytes, flush: true);
    onProgress?.call(0.86);

    // flutter_image_compress may not return exact dims; re-probe when possible.
    final outSize = await _decodeSize(outPath);
    onProgress?.call(1);

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
    void Function(double progress)? onProgress,
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
        onProgress: onProgress,
      );
    } finally {
      try {
        await File(inPath).delete();
      } on FileSystemException catch (error) {
        debugPrint('[ImageCompressor] temp input cleanup failed: $error');
      }
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
