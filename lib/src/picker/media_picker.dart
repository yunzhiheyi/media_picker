import 'package:flutter/material.dart';

import '../models/media_type.dart';
import '../models/picked_media.dart';
import 'media_picker_page.dart';

/// Entry points for picking images / videos from album or files.
class MediaPicker {
  MediaPicker._();

  /// Opens an image-only album picker. The caller owns its entry UI and limit.
  static Future<List<PickedMedia>> pickImages(
    BuildContext context, {
    int maxCount = 1,
    String title = 'Select photos',
  }) => pick(
    context,
    type: MediaPickType.image,
    maxCount: maxCount,
    title: title,
  );

  /// Opens a single-video album picker with the same Hero preview behaviour.
  static Future<List<PickedMedia>> pickVideo(
    BuildContext context, {
    String title = 'Select video',
  }) => pick(context, type: MediaPickType.video, maxCount: 1, title: title);

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
        builder:
            (_) =>
                MediaPickerPage(type: type, maxCount: maxCount, title: title),
      ),
    );
    return result ?? const [];
  }

  /// Request photo-library permission (no-op success on unsupported platforms).
  static Future<bool> requestPermission() =>
      MediaPickerPage.requestPermission();
}
