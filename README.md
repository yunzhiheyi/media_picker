# media_compressor

Flutter plugin for **image / video compression** and **album media picking**.

Extracted for reuse from [yunzhiheyi/video_compressor](https://github.com/yunzhiheyi/video_compressor) (full app → maintainable plugin). Designed to pair with chat SDKs (e.g. MaxAgent) and viewers such as [hero_media_viewer](https://github.com/yunzhiheyi/hero_media_viewer) / [brighton_video_player](https://pub.dev/packages/brighton_video_player).

## Features

| API | Role |
|---|---|
| `ImageCompressor` | Re-encode JPEG/WebP/PNG; strips EXIF/GPS |
| `VideoCompressor` | Probe / compress (H.264+AAC, faststart) / poster frame |
| `MediaPicker` | Album grid (iOS/Android) or file dialog (desktop) |
| `MediaCompressPresets` | Chat defaults (2048 image / 512 thumb / 720p@1.5Mbps) |

## Install

```yaml
dependencies:
  media_compressor:
    git:
      url: https://github.com/yunzhiheyi/media_compressor.git
      ref: v1.0.0
```

### iOS host `Info.plist`

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos or videos to send in chat</string>
```

### Android

Plugin merges `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (and legacy storage ≤32). No extra setup beyond Gradle sync.

## Quick start

```dart
import 'package:media_compressor/media_compressor.dart';

// Pick up to 6 images
final images = await MediaPicker.pick(
  context,
  type: MediaPickType.image,
  maxCount: 6,
);

// Compress for chat upload
final image = await ImageCompressor.compressFile(
  images.first.path,
  options: MediaCompressPresets.chatImage,
);
final thumb = await ImageCompressor.compressFile(
  images.first.path,
  options: MediaCompressPresets.chatThumb,
);

// Video
final videos = await MediaPicker.pick(
  context,
  type: MediaPickType.video,
  maxCount: 1,
);
final compressor = VideoCompressor();
final video = await compressor.compress(
  inputPath: videos.first.path,
  options: MediaCompressPresets.chatVideo,
  onProgress: (p) => debugPrint('${(p * 100).toStringAsFixed(0)}%'),
);
final poster = await compressor.extractPoster(video.path, maxSide: 512);
```

## Platforms

| | iOS | Android | Notes |
|---|---|---|---|
| Image compress | ✅ | ✅ | `flutter_image_compress` |
| Video compress | ✅ | ✅ | `ffmpeg_kit_flutter_new` (VideoToolbox / libx264) |
| Album picker | ✅ | ✅ | `photo_manager` |
| Desktop file pick | ✅ | — | via `file_picker` in example hosts |

## License

MIT
