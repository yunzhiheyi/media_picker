import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:v_video_compressor/v_video_compressor.dart';

import '../models/compress_options.dart';
import '../models/compress_result.dart';
import '../models/video_info.dart';

/// Native video compression backed by Android Media3 and iOS AVFoundation.
///
/// `v_video_compressor` supplies actual native encoder progress. This adapter
/// keeps the package's stable `VideoCompressor` API while exposing that signal
/// to callers that render a compression/upload progress indicator.
class VideoCompressor {
  VideoCompressor({VVideoCompressor? compressor})
    : _compressor = compressor ?? VVideoCompressor();

  final VVideoCompressor _compressor;
  final Set<String> _activeTaskIds = <String>{};

  Future<VideoInfo> probe(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Input video not found: $path');
    }

    final info = await _compressor.getVideoInfo(path);
    if (info == null) return _basicInfo(path);
    return _mapInfo(info, path);
  }

  Future<Uint8List?> extractPoster(
    String videoPath, {
    int? maxSide,
    int quality = 70,
  }) async {
    final thumbnail = await _compressor.getVideoThumbnail(
      videoPath,
      VVideoThumbnailConfig(
        maxWidth: maxSide,
        maxHeight: maxSide,
        quality: quality,
        format: VThumbnailFormat.jpeg,
      ),
    );
    if (thumbnail == null || thumbnail.thumbnailPath.isEmpty) return null;

    final file = File(thumbnail.thumbnailPath);
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } finally {
      try {
        await file.delete();
      } on FileSystemException catch (error) {
        debugPrint('[VideoCompressor] poster cleanup failed: $error');
      }
    }
  }

  /// Compress and yield the native encoder's progress from 0.0 to 1.0.
  Stream<double> compressProgress({
    required String inputPath,
    required VideoCompressOptions options,
  }) {
    final controller = StreamController<double>();
    unawaited(
      _compressToResult(
            inputPath: inputPath,
            options: options,
            onProgress: controller.add,
          )
          .then((_) {
            if (!controller.isClosed) controller.close();
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!controller.isClosed) controller.addError(error, stackTrace);
            if (!controller.isClosed) controller.close();
          }),
    );
    return controller.stream;
  }

  /// Compress a single video using the native platform encoder.
  Future<VideoCompressResult> compress({
    required String inputPath,
    VideoCompressOptions options = const VideoCompressOptions(),
    void Function(double progress)? onProgress,
  }) => _compressToResult(
    inputPath: inputPath,
    options: options,
    onProgress: onProgress,
  );

  Future<void> cancel(String taskId) async {
    if (!_activeTaskIds.remove(taskId)) return;
    await _compressor.cancelCompression();
  }

  Future<bool> isValid(String filePath) async {
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) return false;
    final info = await _compressor.getVideoInfo(filePath);
    return info != null && info.durationMillis > 0;
  }

  void dispose() => _activeTaskIds.clear();

  Future<VideoCompressResult> _compressToResult({
    required String inputPath,
    required VideoCompressOptions options,
    void Function(double progress)? onProgress,
  }) async {
    final input = File(inputPath);
    if (!await input.exists()) {
      throw StateError('Input video not found: $inputPath');
    }

    final originalSize = await input.length();
    final sourceInfo = await probe(inputPath);
    final taskId =
        options.taskId ?? 'video-${DateTime.now().microsecondsSinceEpoch}';
    final config = _configFor(options, sourceInfo);

    _activeTaskIds.add(taskId);
    onProgress?.call(0);
    try {
      final result = await _compressor.compressVideo(
        inputPath,
        config,
        id: taskId,
        onProgress: (progress) {
          onProgress?.call(progress.clamp(0.0, 1.0));
        },
      );
      if (result == null || result.compressedFilePath.isEmpty) {
        throw StateError('Native video compression failed');
      }

      final output = File(result.compressedFilePath);
      if (!await output.exists()) {
        throw StateError('Native video compression did not create an output');
      }
      final info = await probe(result.compressedFilePath);
      onProgress?.call(1);
      return VideoCompressResult(
        path: result.compressedFilePath,
        size:
            result.compressedSizeBytes > 0
                ? result.compressedSizeBytes
                : await output.length(),
        originalSize: originalSize,
        info: info,
      );
    } finally {
      _activeTaskIds.remove(taskId);
    }
  }

  VVideoCompressionConfig _configFor(
    VideoCompressOptions options,
    VideoInfo source,
  ) {
    final dimensions = _targetDimensions(
      width: source.orientatedWidth,
      height: source.orientatedHeight,
      maxSide: options.maxSide,
    );
    return VVideoCompressionConfig(
      quality: _qualityFor(options.maxSide),
      outputPath: options.outputPath,
      includeMetadata: false,
      copyMetadata: false,
      optimizeForStreaming: true,
      useFastStart: true,
      useHardwareAcceleration: true,
      useVariableBitrate: true,
      advanced: VVideoAdvancedConfig(
        videoBitrate: options.bitrate,
        audioBitrate: options.audioBitrate,
        frameRate: options.maxFrameRate,
        videoCodec: VVideoCodec.h264,
        audioCodec: VAudioCodec.aac,
        hardwareAcceleration: true,
        autoCorrectOrientation: true,
        variableBitrate: true,
        dimensionHandling: VDimensionHandling.autoAlign,
        customWidth: dimensions?.$1,
        customHeight: dimensions?.$2,
      ),
    );
  }

  static VVideoCompressQuality _qualityFor(int? maxSide) {
    if (maxSide == null || maxSide >= 1080) {
      return VVideoCompressQuality.high;
    }
    if (maxSide >= 720) return VVideoCompressQuality.medium;
    if (maxSide >= 480) return VVideoCompressQuality.low;
    if (maxSide >= 360) return VVideoCompressQuality.veryLow;
    return VVideoCompressQuality.ultraLow;
  }

  static (int, int)? _targetDimensions({
    required int? width,
    required int? height,
    required int? maxSide,
  }) {
    if (width == null || height == null || maxSide == null) return null;
    if (width <= 0 || height <= 0 || width <= maxSide && height <= maxSide) {
      return null;
    }
    final scale = maxSide / (width > height ? width : height);
    return ((width * scale).round(), (height * scale).round());
  }

  static VideoInfo _mapInfo(VVideoInfo info, String fallbackPath) {
    return VideoInfo(
      path: info.path.isEmpty ? fallbackPath : info.path,
      name: info.name,
      size: info.fileSizeBytes,
      duration: Duration(milliseconds: info.durationMillis),
      width: info.width,
      height: info.height,
      thumbnailBytes: null,
    );
  }

  static VideoInfo _basicInfo(String path) {
    final file = File(path);
    return VideoInfo(
      path: path,
      name: path.split(Platform.pathSeparator).last,
      size: file.statSync().size,
    );
  }
}
