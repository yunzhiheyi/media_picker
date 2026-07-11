// Integration smoke: package resolves and presets are wired.
import 'package:flutter_test/flutter_test.dart';
import 'package:media_compressor/media_compressor.dart';

void main() {
  testWidgets('presets available in example host', (tester) async {
    expect(MediaCompressPresets.chatVideo.maxSide, 720);
  });
}
