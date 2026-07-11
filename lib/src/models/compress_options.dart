/// Image compression options.
class ImageCompressOptions {
  /// Long-edge pixel limit. The other edge scales to keep aspect ratio.
  final int maxSide;

  /// JPEG/WebP quality 1–100.
  final int quality;

  /// Soft size budget in bytes. When set, quality steps down until under budget
  /// or [minQuality] is reached.
  final int? maxBytes;

  /// Floor quality when applying [maxBytes].
  final int minQuality;

  /// Output format. Prefer jpeg for chat uploads (EXIF stripped by re-encode).
  final ImageOutputFormat format;

  const ImageCompressOptions({
    this.maxSide = 2048,
    this.quality = 85,
    this.maxBytes,
    this.minQuality = 40,
    this.format = ImageOutputFormat.jpeg,
  });
}

enum ImageOutputFormat { jpeg, webp, png }

/// Video compression options.
class VideoCompressOptions {
  /// Target long-edge (e.g. 720 for 720p). Null keeps original resolution.
  final int? maxSide;

  /// Target video bitrate in bps. When original bitrate is lower, original is used.
  final int bitrate;

  /// Audio bitrate in bps.
  final int audioBitrate;

  /// Cap frame rate when original exceeds this (null = keep).
  final double? maxFrameRate;

  /// Optional explicit output path. When null a temp file is created.
  final String? outputPath;

  /// Task id for cancel / progress tracking.
  final String? taskId;

  const VideoCompressOptions({
    this.maxSide = 720,
    this.bitrate = 1500000,
    this.audioBitrate = 128000,
    this.maxFrameRate = 30,
    this.outputPath,
    this.taskId,
  });
}
