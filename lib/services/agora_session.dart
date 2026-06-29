import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../api/session_api.dart';

/// Thin wrapper around the Agora RTC engine for one call/video session on the
/// astrologer side. Recording is server-side (recordingService) — this only
/// joins/leaves and exposes remote-user state. Mirrors the user app's helper.
///
/// If the backend runs Agora in MOCK mode (no app id/token), [join] is a no-op
/// and the session still runs as a timed consultation.
class AgoraSession {
  RtcEngine? _engine;
  bool _joined = false;
  bool get joined => _joined;

  int? remoteUid;
  bool muted = false;
  bool cameraOff = false;
  bool speakerOn = true;

  // Surfaces a real, fatal Agora error (token rejected = err 110/109, etc.).
  final ValueNotifier<String?> errorNotifier = ValueNotifier(null);

  RtcEngine? get engine => _engine;

  Future<bool> join(RtcToken token, {required bool video}) async {
    // Need at least an App ID; token may be EMPTY in "App ID only" mode.
    if (token.appId.isEmpty) return false;
    await [Permission.microphone, if (video) Permission.camera].request();

    final engine = createAgoraRtcEngine();
    await engine.initialize(RtcEngineContext(
      appId: token.appId,
      channelProfile: ChannelProfileType.channelProfileCommunication,
    ));
    _engine = engine;

    engine.registerEventHandler(RtcEngineEventHandler(
      onUserJoined: (conn, uid, elapsed) {
        remoteUid = uid;
        debugPrint('[Agora] remote user joined uid=$uid');
        // Be explicit about subscribing to the peer so media actually arrives.
        try { engine.muteRemoteAudioStream(uid: uid, mute: false); } catch (_) {}
        if (video) {
          try { engine.muteRemoteVideoStream(uid: uid, mute: false); } catch (_) {}
        }
      },
      onUserOffline: (conn, uid, reason) { if (remoteUid == uid) remoteUid = null; },
      onJoinChannelSuccess: (conn, elapsed) {
        _joined = true;
        debugPrint('[Agora] joined ${conn.channelId} uid ${conn.localUid}');
      },
      onError: (err, msg) {
        debugPrint('[Agora] ERROR $err: $msg');
        if (err == ErrorCodeType.errTokenExpired ||
            err == ErrorCodeType.errInvalidToken ||
            err == ErrorCodeType.errInvalidAppId ||
            err == ErrorCodeType.errInvalidChannelName) {
          errorNotifier.value = 'Media connection failed ($err). '
              'Check the Agora App Certificate / security mode.';
        }
      },
      onConnectionStateChanged: (conn, state, reason) {
        debugPrint('[Agora] connection state=$state reason=$reason');
        if (state == ConnectionStateType.connectionStateFailed &&
            reason == ConnectionChangedReasonType.connectionChangedInvalidToken) {
          errorNotifier.value = 'Media connection failed: invalid token. '
              'Check the Agora App Certificate / security mode.';
        }
      },
    ));

    await engine.enableAudio();
    try {
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileDefault,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );
    } catch (_) {}
    try { await engine.setDefaultAudioRouteToSpeakerphone(true); } catch (_) {}
    if (video) {
      await engine.enableVideo();
      await engine.startPreview();
    }
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await engine.joinChannel(
      token: token.token.isEmpty ? '' : token.token,
      channelId: token.channelName,
      uid: token.uid,
      // Explicitly PUBLISH mic (+ camera for video) and AUTO-SUBSCRIBE to the
      // other party's media — without these the peer joins but no media flows.
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileCommunication,
        publishMicrophoneTrack: true,
        publishCameraTrack: video,
        autoSubscribeAudio: true,
        autoSubscribeVideo: video,
      ),
    );
    try { await engine.muteAllRemoteAudioStreams(false); } catch (_) {}
    if (video) { try { await engine.muteAllRemoteVideoStreams(false); } catch (_) {} }
    // setEnableSpeakerphone requires being IN a channel — calling it pre-join
    // throws AgoraRtcException(-3) and aborts the join (no audio). Do it after.
    try { await engine.setEnableSpeakerphone(true); } catch (_) {}
    return true;
  }

  Future<void> toggleMute() async { muted = !muted; await _engine?.muteLocalAudioStream(muted); }
  Future<void> toggleCamera() async { cameraOff = !cameraOff; await _engine?.muteLocalVideoStream(cameraOff); }
  Future<void> switchCamera() async { try { await _engine?.switchCamera(); } catch (_) {} }
  Future<void> toggleSpeaker() async { speakerOn = !speakerOn; try { await _engine?.setEnableSpeakerphone(speakerOn); } catch (_) {} }

  Future<void> leave() async {
    try { await _engine?.leaveChannel(); await _engine?.release(); } catch (_) {}
    _engine = null;
    _joined = false;
    remoteUid = null;
  }

  void dispose() {
    errorNotifier.dispose();
  }
}
