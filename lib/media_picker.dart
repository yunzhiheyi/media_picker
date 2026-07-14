/// Media picking, Hero preview, and media compression for Flutter.
///
/// The picker is intentionally independent of business UI: consumers choose
/// when to call [MediaPicker.pickImages] or [MediaPicker.pickVideo].
library;

export 'src/image/image_compressor.dart';
export 'src/models/compress_options.dart';
export 'src/models/compress_result.dart';
export 'src/models/media_type.dart';
export 'src/models/picked_media.dart';
export 'src/models/video_info.dart';
export 'src/picker/media_picker.dart';
export 'src/picker/media_picker_page.dart';
export 'src/presets.dart';
export 'src/video/video_compressor.dart';
