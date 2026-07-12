## 1.1.0

- **BREAKING(合规)**: `ffmpeg_kit_flutter_new`(full-gpl,含 libx264)替换为
  `ffmpeg_kit_flutter_new_min` ^3.4.0(LGPL v3,min 构建)。闭源商业 SDK 再分发
  不再被 GPL 传染,原生体积显著下降。
- Android 视频编码 libx264(软编)→ `h264_mediacodec`(硬件编码);Apple 端保持
  `h264_videotoolbox`。profile/level 参数仅对 videotoolbox 下发。

# Changelog

## 1.0.0

- Initial plugin release extracted from `yunzhiheyi/video_compressor`
- `ImageCompressor` with EXIF-stripping re-encode + optional maxBytes quality ladder
- `VideoCompressor` probe / compress / poster / cancel
- `MediaPicker` + `MediaPickerPage` (album grid + desktop file dialog)
- `MediaCompressPresets` chat defaults (2048 / 512 / 720p@1.5Mbps)
