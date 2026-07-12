import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/statistics.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/compress_options.dart';
import '../models/compress_result.dart';
import '../models/video_info.dart';

/// Hardware-accelerated video probe / compress / poster extraction via FFmpeg.
///
/// Logic ported from yunzhiheyi/video_compressor `FFmpegService`, cleaned for
/// plugin reuse. Android uses h264_mediacodec; Apple platforms use
/// h264_videotoolbox — both hardware encoders on the LGPL min build.
class VideoCompressor {
  VideoCompressor();

  final Map<String, double> _progressMap = {};
  final Map<String, int> _sessionIdMap = {};

  Future<VideoInfo> probe(String path) async {
    try {
      final session = await FFprobeKit.execute(
        '-v quiet -print_format json -show_format -show_streams "$path"',
      );
      final json = await session.getOutput();
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) && json != null && json.isNotEmpty) {
        return _parseProbe(json, path);
      }
    } catch (e) {
      debugPrint('[VideoCompressor] probe failed: $e');
    }
    return _basicInfo(path);
  }

  Future<Uint8List?> extractPoster(
    String videoPath, {
    int? maxSide,
    int quality = 2,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbPath = p.join(
        tempDir.path,
        'mc_poster_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      final scale = maxSide == null
          ? ''
          : ' -vf "scale=\'min($maxSide,iw)\':\'min($maxSide,ih)\':force_original_aspect_ratio=decrease"';
      final command =
          '-ss 0 -i "$videoPath"$scale -vframes 1 -q:v $quality -y "$thumbPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) return null;

      final file = File(thumbPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes;
    } catch (e) {
      debugPrint('[VideoCompressor] poster failed: $e');
      return null;
    }
  }

  /// Compress and yield progress 0.0–1.0. Throws on failure / timeout / cancel.
  Stream<double> compressProgress({
    required String inputPath,
    required VideoCompressOptions options,
  }) async* {
    final id = options.taskId ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      throw StateError('Input video not found: $inputPath');
    }
    final originalSize = await inputFile.length();

    final info = await probe(inputPath);
    final outPath = options.outputPath ?? await _defaultOutputPath();
    final outFile = File(outPath);
    if (!await outFile.parent.exists()) {
      await outFile.parent.create(recursive: true);
    }

    var targetBitrate = options.bitrate;
    if (info.bitrate != null &&
        info.bitrate! > 0 &&
        info.bitrate! <= options.bitrate) {
      targetBitrate = info.bitrate!;
    }

    final command = _buildCommand(
      inputPath: inputPath,
      outputPath: outPath,
      bitrate: targetBitrate,
      audioBitrate: options.audioBitrate,
      maxSide: options.maxSide,
      originalWidth: info.width,
      originalHeight: info.height,
      originalFrameRate: info.frameRate,
      maxFrameRate: options.maxFrameRate,
    );

    yield 0.0;

    final completer = Completer<void>();
    var lastProgress = 0.0;
    var hasError = false;
    String? errorMessage;
    int? sessionId;
    final durationSec = info.duration?.inMilliseconds != null
        ? info.duration!.inMilliseconds / 1000.0
        : null;

    try {
      final session = await FFmpegKit.executeAsync(
        command,
        (session) async {
          final returnCode = await session.getReturnCode();
          final output = await session.getOutput();
          if (ReturnCode.isSuccess(returnCode)) {
            _progressMap[id] = 1.0;
          } else {
            _progressMap[id] = -1.0;
            hasError = true;
            errorMessage = output ?? 'FFmpeg error';
          }
          _sessionIdMap.remove(id);
          if (!completer.isCompleted) completer.complete();
        },
        null,
        (Statistics statistics) {
          final time = statistics.getTime();
          if (time <= 0) return;
          double progress;
          if (durationSec != null && durationSec > 0) {
            progress = (time / 1000.0) / durationSec;
          } else {
            progress = ((time / 1000.0) / 300.0).clamp(0.0, 0.99);
          }
          _progressMap[id] = progress.clamp(0.0, 0.99);
        },
      );
      sessionId = session.getSessionId();
      if (sessionId != null) _sessionIdMap[id] = sessionId;
    } catch (e) {
      hasError = true;
      errorMessage = e.toString();
      if (!completer.isCompleted) completer.complete();
    }

    var waitCount = 0;
    const maxWait = 1200; // 120s @ 100ms
    while (!completer.isCompleted && waitCount < maxWait) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
      final progress = _progressMap[id];
      if (progress != null && progress < 0) {
        throw StateError(errorMessage ?? 'Compression failed');
      }
      if (progress != null && progress > lastProgress) {
        yield progress;
        lastProgress = progress;
      }
    }

    if (!completer.isCompleted) {
      if (sessionId != null) await FFmpegKit.cancel(sessionId);
      _sessionIdMap.remove(id);
      _progressMap.remove(id);
      throw TimeoutException('Video compression timeout');
    }

    _sessionIdMap.remove(id);
    _progressMap.remove(id);

    if (hasError) {
      throw StateError(errorMessage ?? 'Compression failed');
    }

    // Touch originalSize so callers can compare after stream completes via
    // [compress] helper. Progress stream itself only yields doubles.
    assert(originalSize >= 0);
    yield 1.0;
  }

  /// Convenience: wait for compress and return result with paths/sizes.
  Future<VideoCompressResult> compress({
    required String inputPath,
    VideoCompressOptions options = const VideoCompressOptions(),
    void Function(double progress)? onProgress,
  }) async {
    final originalSize = await File(inputPath).length();
    final outPath = options.outputPath ?? await _defaultOutputPath();
    final opts = VideoCompressOptions(
      maxSide: options.maxSide,
      bitrate: options.bitrate,
      audioBitrate: options.audioBitrate,
      maxFrameRate: options.maxFrameRate,
      outputPath: outPath,
      taskId: options.taskId,
    );

    await for (final p in compressProgress(inputPath: inputPath, options: opts)) {
      onProgress?.call(p);
    }

    final size = await File(outPath).length();
    final info = await probe(outPath);
    return VideoCompressResult(
      path: outPath,
      size: size,
      originalSize: originalSize,
      info: info,
    );
  }

  Future<void> cancel(String taskId) async {
    final sessionId = _sessionIdMap[taskId];
    if (sessionId != null) {
      await FFmpegKit.cancel(sessionId);
      _sessionIdMap.remove(taskId);
    }
    _progressMap[taskId] = -1.0;
  }

  Future<bool> isValid(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() == 0) return false;
      final session = await FFprobeKit.execute(
        '-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      final output = await session.getOutput();
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode) ||
          output == null ||
          output.trim().isEmpty) {
        return false;
      }
      final duration = double.tryParse(output.trim());
      return duration != null && duration > 0;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _progressMap.clear();
    _sessionIdMap.clear();
  }

  VideoInfo _parseProbe(String jsonStr, String path) {
    try {
      final jsonData = jsonDecode(jsonStr) as Map<String, dynamic>;
      String? duration;
      String? width;
      String? height;
      String? codec;
      String? bitrate;
      String? frameRate;
      int? size;
      int? rotation;

      final format = jsonData['format'] as Map<String, dynamic>?;
      if (format != null) {
        duration = format['duration']?.toString();
        bitrate = format['bit_rate']?.toString();
        if (format['size'] != null) {
          size = int.tryParse(format['size'].toString());
        }
      }

      final streams = jsonData['streams'] as List<dynamic>?;
      if (streams != null) {
        for (final stream in streams) {
          if (stream['codec_type'] != 'video') continue;
          width = stream['width']?.toString();
          height = stream['height']?.toString();
          codec = stream['codec_name']?.toString();

          final frameRateStr = stream['avg_frame_rate']?.toString();
          if (frameRateStr != null && frameRateStr.contains('/')) {
            final parts = frameRateStr.split('/');
            if (parts.length == 2) {
              final num = double.tryParse(parts[0]);
              final den = double.tryParse(parts[1]);
              if (num != null && den != null && den != 0) {
                frameRate = (num / den).toStringAsFixed(2);
              }
            }
          } else if (frameRateStr != null) {
            frameRate = frameRateStr;
          }

          final sideDataList = stream['side_data_list'] as List<dynamic>?;
          if (sideDataList != null) {
            for (final sideData in sideDataList) {
              if (sideData['rotation'] != null) {
                rotation = int.tryParse(sideData['rotation'].toString());
                break;
              }
            }
          }
          if (rotation == null) {
            final tags = stream['tags'] as Map<String, dynamic>?;
            if (tags != null && tags['rotate'] != null) {
              rotation = int.tryParse(tags['rotate'].toString());
            }
          }
          if (rotation == null && stream['display_rotation'] != null) {
            rotation = int.tryParse(stream['display_rotation'].toString());
          }
          break;
        }
      }

      final durationSec = duration != null ? double.tryParse(duration) : null;

      return VideoInfo(
        path: path,
        name: p.basename(path),
        size: size,
        duration: durationSec == null
            ? null
            : Duration(milliseconds: (durationSec * 1000).round()),
        width: width != null ? int.tryParse(width) : null,
        height: height != null ? int.tryParse(height) : null,
        codec: codec,
        bitrate: bitrate != null ? int.tryParse(bitrate) : null,
        frameRate: frameRate != null ? double.tryParse(frameRate) : null,
        rotation: rotation,
      );
    } catch (e) {
      debugPrint('[VideoCompressor] parse probe failed: $e');
      return _basicInfo(path);
    }
  }

  VideoInfo _basicInfo(String path) {
    final file = File(path);
    final stat = file.statSync();
    return VideoInfo(
      path: path,
      name: p.basename(path),
      size: stat.size,
    );
  }

  String _buildCommand({
    required String inputPath,
    required String outputPath,
    required int bitrate,
    required int audioBitrate,
    required int? maxSide,
    required int? originalWidth,
    required int? originalHeight,
    required double? originalFrameRate,
    required double? maxFrameRate,
  }) {
    final buffer = StringBuffer();
    buffer.write('-i "$inputPath"');

    // 双端硬件编码器(min/LGPL 构建无 libx264,也不允许引入 GPL 软编):
    // Android 走 MediaCodec,Apple 走 VideoToolbox
    final videoCodec =
        Platform.isAndroid ? 'h264_mediacodec' : 'h264_videotoolbox';
    buffer.write(' -c:v $videoCodec');

    final targetBitrate = bitrate <= 0 ? 1500000 : bitrate;
    buffer.write(' -b:v $targetBitrate');
    buffer.write(' -maxrate ${(targetBitrate * 1.3).toInt()}');
    buffer.write(' -bufsize ${(targetBitrate * 2.5).toInt()}');
    if (!Platform.isAndroid) {
      // profile/level 只对 videotoolbox 下发;mediacodec 对无效参数直接报错,
      // 交给设备默认 profile 更稳
      buffer.write(' -profile:v high');
      buffer.write(' -level 4.2');
    }
    buffer.write(' -c:a aac');
    buffer.write(' -b:a $audioBitrate');

    String? scaleFilter;
    if (maxSide != null &&
        originalWidth != null &&
        originalHeight != null &&
        originalWidth > 0 &&
        originalHeight > 0) {
      final isLandscape = originalWidth >= originalHeight;
      // Long-edge constraint: landscape → height=maxSide; portrait → width=maxSide
      scaleFilter = isLandscape ? 'scale=-2:$maxSide' : 'scale=$maxSide:-2';
    } else if (maxSide != null) {
      scaleFilter = 'scale=-2:$maxSide';
    }

    String? fpsFilter;
    if (maxFrameRate != null &&
        originalFrameRate != null &&
        originalFrameRate > maxFrameRate) {
      fpsFilter = 'fps=${maxFrameRate.toStringAsFixed(0)}';
    }

    if (scaleFilter != null && fpsFilter != null) {
      buffer.write(' -vf "$scaleFilter,$fpsFilter"');
    } else if (scaleFilter != null) {
      buffer.write(' -vf "$scaleFilter"');
    } else if (fpsFilter != null) {
      buffer.write(' -vf "$fpsFilter"');
    }

    buffer.write(' -movflags +faststart');
    buffer.write(' -y "$outputPath"');
    return buffer.toString();
  }

  Future<String> _defaultOutputPath() async {
    final dir = await getTemporaryDirectory();
    return p.join(
      dir.path,
      'mc_vid_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
  }
}
