import 'package:flutter_test/flutter_test.dart';
import 'package:media_picker/media_picker.dart';

void main() {
  test('chat presets match SDK media table', () {
    expect(MediaCompressPresets.chatImage.maxSide, 2048);
    expect(MediaCompressPresets.chatImage.quality, 85);
    expect(MediaCompressPresets.chatThumb.maxSide, 512);
    expect(MediaCompressPresets.chatThumb.maxBytes, 50 * 1024);
    expect(MediaCompressPresets.chatVideo.maxSide, 720);
    expect(MediaCompressPresets.chatVideo.bitrate, 1500000);
  });

  test('VideoInfo formats duration and size', () {
    const info = VideoInfo(
      path: '/tmp/a.mp4',
      size: 1536,
      duration: Duration(minutes: 1, seconds: 5),
      width: 1280,
      height: 720,
    );
    expect(info.durationFormatted, '01:05');
    expect(info.sizeFormatted, '1.5 KB');
    expect(info.orientatedWidth, 1280);
  });
}
