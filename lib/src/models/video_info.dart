import 'dart:typed_data';

/// Probed video metadata.
class VideoInfo {
  final String path;
  final String? name;
  final int? size;
  final Duration? duration;
  final int? width;
  final int? height;
  final String? codec;
  final int? bitrate;
  final double? frameRate;
  final int? rotation;
  final Uint8List? thumbnailBytes;

  const VideoInfo({
    required this.path,
    this.name,
    this.size,
    this.duration,
    this.width,
    this.height,
    this.codec,
    this.bitrate,
    this.frameRate,
    this.rotation,
    this.thumbnailBytes,
  });

  int? get orientatedWidth {
    if (width == null || height == null) return null;
    if (rotation != null && (rotation!.abs() == 90 || rotation!.abs() == 270)) {
      return height;
    }
    return width;
  }

  int? get orientatedHeight {
    if (width == null || height == null) return null;
    if (rotation != null && (rotation!.abs() == 90 || rotation!.abs() == 270)) {
      return width;
    }
    return height;
  }

  String get sizeFormatted => _formatFileSize(size ?? 0);

  String get durationFormatted {
    if (duration == null) return '00:00';
    final h = duration!.inHours;
    final m = duration!.inMinutes.remainder(60);
    final s = duration!.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  VideoInfo copyWith({
    String? path,
    String? name,
    int? size,
    Duration? duration,
    int? width,
    int? height,
    String? codec,
    int? bitrate,
    double? frameRate,
    int? rotation,
    Uint8List? thumbnailBytes,
  }) {
    return VideoInfo(
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      codec: codec ?? this.codec,
      bitrate: bitrate ?? this.bitrate,
      frameRate: frameRate ?? this.frameRate,
      rotation: rotation ?? this.rotation,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
    );
  }
}
