# media_picker

Flutter package for **image / video selection**, **Hero preview**, and
**compression**. The host application owns attachment-entry UI and calls the
image/video APIs it needs.

Extracted for reuse from [yunzhiheyi/video_compressor](https://github.com/yunzhiheyi/video_compressor) (full app → maintainable plugin). Designed to pair with chat SDKs (e.g. MaxAgent) and viewers such as [hero_media_viewer](https://github.com/yunzhiheyi/hero_media_viewer) / [brighton_video_player](https://pub.dev/packages/brighton_video_player).

## Features

| API | Role |
|---|---|
| `ImageCompressor` | Re-encode JPEG/WebP/PNG; strips EXIF/GPS |
| `VideoCompressor` | Probe / compress (H.264+AAC, faststart) / poster frame |
| `MediaPicker` | Separate image/video picker APIs; Hero image/video preview |
| `MediaCompressPresets` | Chat defaults (2048 image / 512 thumb / 720p@1.5Mbps) |

## Install

```yaml
dependencies:
  media_picker:
    git:
      url: https://github.com/yunzhiheyi/media_picker.git
      ref: v1.0.0
```

### iOS host `Info.plist`

`media_picker` has an iOS 14.0 deployment target. It uses native AVFoundation
for video compression, so no FFmpeg framework or static-header workaround is
required.

```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Select photos or videos to send in chat</string>
```

### Android

Plugin merges `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (and legacy storage ≤32). No extra setup beyond Gradle sync.

## Quick start

```dart
import 'package:media_picker/media_picker.dart';

// Pick up to 6 images
final images = await MediaPicker.pickImages(
  context,
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
final videos = await MediaPicker.pickVideo(context);
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
| Video compress | ✅ | ✅ | `v_video_compressor` (AVFoundation / Media3) |
| Album picker | ✅ | ✅ | `photo_manager` |
| Desktop file pick | ✅ | — | via `file_picker` in example hosts |

## License

MIT
