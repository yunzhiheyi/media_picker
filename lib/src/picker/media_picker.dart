import 'package:flutter/material.dart';

import '../models/media_type.dart';
import '../models/picked_media.dart';
import 'media_picker_page.dart';

/// Entry points for picking images / videos from album or files.
class MediaPicker {
  MediaPicker._();

  /// Opens a full-screen picker and returns selected media (empty if cancelled).
  static Future<List<PickedMedia>> pick(
    BuildContext context, {
    MediaPickType type = MediaPickType.both,
    int maxCount = 1,
    String title = 'Select media',
  }) async {
    final result = await Navigator.of(context).push<List<PickedMedia>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaPickerPage(
          type: type,
          maxCount: maxCount,
          title: title,
        ),
      ),
    );
    return result ?? const [];
  }

  /// Request photo-library permission (no-op success on unsupported platforms).
  static Future<bool> requestPermission() => MediaPickerPage.requestPermission();
}
