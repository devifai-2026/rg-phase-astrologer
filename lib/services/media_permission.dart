import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// Resolves the correct "gallery / photos" runtime permission across every
/// Android version (9 → latest) and iOS. Mirrors the user app.
///
/// The trap: `permission_handler`'s [Permission.photos] maps to Android's
/// `READ_MEDIA_IMAGES`, which only EXISTS on Android 13 (API 33+). On API ≤ 32
/// (Android 9–12) requesting it silently no-ops; those versions gate gallery
/// access behind `READ_EXTERNAL_STORAGE` (i.e. [Permission.storage]).
class MediaPermission {
  static final _deviceInfo = DeviceInfoPlugin();
  static int? _androidSdkCache; // memoized — OS version can't change at runtime

  /// Cached Android SDK int (e.g. 28 for Android 9). 0 on non-Android.
  static Future<int> androidSdk() async {
    if (!Platform.isAndroid) return 0;
    return _androidSdkCache ??= (await _deviceInfo.androidInfo).version.sdkInt;
  }

  /// The Permission that actually drives photo-library access on this device.
  static Future<Permission> photos() async {
    if (!Platform.isAndroid) return Permission.photos; // iOS
    final sdk = await androidSdk();
    return sdk >= 33 ? Permission.photos : Permission.storage;
  }
}
