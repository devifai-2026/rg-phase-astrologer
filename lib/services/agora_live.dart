import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/session_api.dart' show RtcToken;

/// Agora helper for the astrologer's LIVE BROADCAST (one-to-many). The
/// astrologer is the sole BROADCASTER (publishes audio + video) in a
/// live-broadcasting profile channel; viewers join as audience elsewhere.
///
/// Falls back to a no-op (returns false) if Agora runs in App-ID-only / mock
/// mode with no app id, so the broadcast UI can still render a placeholder.
class AgoraLive {
  RtcEngine? _engine;
  bool _joined = false;
  bool get joined => _joined;
  RtcEngine? get engine => _engine;

  bool camOff = false;
  bool muted = false;

  // Surfaces a fatal Agora error (invalid token = err 110/109, etc.).
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  Future<bool> startBroadcast(RtcToken token) async {
    if (token.appId.isEmpty) return false;
    await [Permission.microphone, Permission.camera].request();

    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: token.appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    _engine = engine;

    engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (conn, elapsed) {
        _joined = true;
        debugPrint('[AgoraLive] broadcasting on ${conn.channelId} uid ${conn.localUid}');
      },
      onError: (err, msg) {
        debugPrint('[AgoraLive] ERROR $err: $msg');
        if (err == ErrorCodeType.errTokenExpired ||
            err == ErrorCodeType.errInvalidToken ||
            err == ErrorCodeType.errInvalidAppId) {
          errorNotifier.value = 'Live media failed ($err). Check the Agora App Certificate / security mode.';
        }
      },
    ));

    await engine.enableAudio();
    await engine.enableVideo();
    await engine.startPreview();
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.joinChannel(
      token: token.token,
      channelId: token.channelName,
      uid: token.uid,
      options: const ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        publishMicrophoneTrack: true,
        publishCameraTrack: true,
      ),
    );
    return true;
  }

  Future<void> toggleCamera() async {
    camOff = !camOff;
    await _engine?.muteLocalVideoStream(camOff);
    if (camOff) {
      await _engine?.stopPreview();
    } else {
      await _engine?.startPreview();
    }
  }

  Future<void> toggleMute() async {
    muted = !muted;
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> switchCamera() async {
    try { await _engine?.switchCamera(); } catch (_) {}
  }

  Future<void> stop() async {
    try { await _engine?.leaveChannel(); await _engine?.release(); } catch (_) {}
    _engine = null;
    _joined = false;
  }

  void dispose() => errorNotifier.dispose();
}
