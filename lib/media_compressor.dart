/// Media compression + album picker for Flutter.
///
/// Capabilities:
/// - Image re-encode / thumbnail generation (`ImageCompressor`)
/// - Video probe / compress / poster frame (`VideoCompressor`)
/// - Album / file picker UI (`MediaPicker`)
///
/// Chat-oriented defaults live in [MediaCompressPresets].
library;

export 'src/models/compress_options.dart';
export 'src/models/compress_result.dart';
export 'src/models/media_type.dart';
export 'src/models/picked_media.dart';
export 'src/models/video_info.dart';
export 'src/image/image_compressor.dart';
export 'src/video/video_compressor.dart';
export 'src/picker/media_picker.dart';
export 'src/picker/media_picker_page.dart';
export 'src/presets.dart';
