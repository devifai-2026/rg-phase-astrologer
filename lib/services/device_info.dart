import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Collects a stable device identity (id + human-readable name/model/OS) so the
/// backend can record *which* phones an account is signed in on — surfaced in
/// the admin console's "Logged-in devices" list. Captured once and sent with
/// the FCM token on register.
///
/// `deviceId` is a per-install stable id:
///   • Android → `androidId` (Settings.Secure.ANDROID_ID)
///   • iOS     → identifierForVendor
/// It survives token rotation, so the backend dedups device rows by it.
class DeviceInfo {
  static final _plugin = DeviceInfoPlugin();
  static Map<String, String>? _cache; // OS/hardware can't change at runtime

  /// Returns { deviceId, deviceName, deviceModel, osVersion } — best-effort,
  /// never throws (push registration must not be blocked by this).
  static Future<Map<String, String>> collect() async {
    if (_cache != null) return _cache!;
    final out = <String, String>{};
    try {
      if (Platform.isAndroid) {
        final a = await _plugin.androidInfo;
        out['deviceId'] = a.id; // ANDROID_ID-derived, stable per install
        out['deviceName'] = '${a.manufacturer} ${a.model}'.trim();
        out['deviceModel'] = a.model;
        out['osVersion'] = 'Android ${a.version.release} (SDK ${a.version.sdkInt})';
      } else if (Platform.isIOS) {
        final i = await _plugin.iosInfo;
        out['deviceId'] = i.identifierForVendor ?? '';
        out['deviceName'] = i.name; // e.g. "Subho's iPhone"
        out['deviceModel'] = i.utsname.machine; // e.g. "iPhone15,3"
        out['osVersion'] = 'iOS ${i.systemVersion}';
      }
    } catch (_) {
      // best-effort — return whatever we gathered
    }
    out.removeWhere((_, v) => v.isEmpty);
    return _cache = out;
  }
}
