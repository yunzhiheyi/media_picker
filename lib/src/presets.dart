import 'models/compress_options.dart';

/// Defaults aligned with MaxAgent SDK chat media rules.
class MediaCompressPresets {
  MediaCompressPresets._();

  /// Re-encoded "original" for chat: long edge ≤2048, q≈0.85 JPEG.
  static const ImageCompressOptions chatImage = ImageCompressOptions(
    maxSide: 2048,
    quality: 85,
    format: ImageOutputFormat.jpeg,
  );

  /// Chat list thumbnail: long edge ≤512, soft ≤50KB.
  static const ImageCompressOptions chatThumb = ImageCompressOptions(
    maxSide: 512,
    quality: 70,
    maxBytes: 50 * 1024,
    minQuality: 40,
    format: ImageOutputFormat.jpeg,
  );

  /// Chat video: H.264 + AAC, long edge 720, ~1.5 Mbps, fps≤30, faststart.
  static const VideoCompressOptions chatVideo = VideoCompressOptions(
    maxSide: 720,
    bitrate: 1500000,
    audioBitrate: 128000,
    maxFrameRate: 30,
  );
}
