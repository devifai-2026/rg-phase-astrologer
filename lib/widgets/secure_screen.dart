import 'package:flutter/widgets.dart';
import 'package:no_screenshot/no_screenshot.dart';

/// Screenshot / screen-recording protection for sensitive screens.
///
/// Under the hood this sets Android's `FLAG_SECURE` (which blocks both
/// screenshots and screen recording, and shows a black frame in the recents
/// switcher) and the iOS equivalent, via the `no_screenshot` package.
///
/// ## Auto-managing usage (recommended)
/// Mix [SecureScreenMixin] into a `State` and protection is enabled in
/// `initState` and disabled again in `dispose` — no other wiring needed:
///
/// ```dart
/// class _ChatScreenState extends State<ChatScreen> with SecureScreenMixin {
///   // ...nothing to do; the screen is secure while mounted.
/// }
/// ```
///
/// ## Manual control
/// If you need finer control (e.g. only while a media overlay is open), call
/// the helpers in [SecureScreen] directly:
///
/// ```dart
/// await SecureScreen.enable();  // block screenshots
/// await SecureScreen.disable(); // restore normal capture
/// ```
///
/// All calls are wrapped in try/catch and never throw, so an unsupported
/// platform or a failed channel call degrades gracefully to a no-op.
class SecureScreen {
  const SecureScreen._();

  /// Block screenshots / screen recording. Safe to call repeatedly.
  static Future<void> enable() async {
    try {
      await NoScreenshot.instance.screenshotOff();
    } catch (_) {
      // Best-effort: never let secure-mode toggling crash a screen.
    }
  }

  /// Restore normal screenshot / recording behaviour. Safe to call repeatedly.
  static Future<void> disable() async {
    try {
      await NoScreenshot.instance.screenshotOn();
    } catch (_) {
      // Best-effort: never let secure-mode toggling crash a screen.
    }
  }
}

/// Drop-in mixin that keeps a screen secure for its whole lifetime: it enables
/// screenshot protection in [initState] and restores normal capture in
/// [dispose]. Both overrides call `super`, so it composes with other mixins.
///
/// ```dart
/// class _FooState extends State<Foo> with SecureScreenMixin { ... }
/// ```
///
/// For manual / partial control, skip the mixin and call
/// [SecureScreen.enable] / [SecureScreen.disable] directly, or call the
/// [enableSecure] / [disableSecure] helpers exposed here.
mixin SecureScreenMixin<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    enableSecure();
  }

  @override
  void dispose() {
    disableSecure();
    super.dispose();
  }

  /// Block screenshots / screen recording for this screen.
  Future<void> enableSecure() => SecureScreen.enable();

  /// Restore normal screenshot / recording behaviour for this screen.
  Future<void> disableSecure() => SecureScreen.disable();
}
