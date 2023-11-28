import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const appId = "2829db8174a54c4dbd2bc24a543ae2d1";
const token =
    "007eJxTYJhkrN9U/Ga3+1e9lCcLZ203Mg1ou+QQuLppourPN9sYf+1TYDCyMLJMSbIwNDdJNDVJNklJSjFKSjYCcYwTU41SDE8wpKU2BDIyKP4qYmJkgEAQX4XBIMncICkxOUXX1NLERNfE3DxJN9E40UzXMtHE3MzE1MDU1NyEgQEASTEoAA==";
const channel = "0b70bacd-5944-477b-a3a6-9a4764505574";

void main() => runApp(const MaterialApp(home: MyApp()));

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _isScreenShared = false;
  late RtcEngineEx _engine;
  final MethodChannel _iosScreenShareChannel =
      const MethodChannel('example_screensharing_ios');

  @override
  void initState() {
    super.initState();
    initAgora();
  }

  Future<void> initAgora() async {
    // retrieve permissions
    await [Permission.microphone, Permission.camera].request();

    //create the engine
    _engine = createAgoraRtcEngineEx();
    await _engine.initialize(const RtcEngineContext(
      appId: appId,
      channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
    ));
    await _engine.setLogLevel(LogLevel.logLevelError);

    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          debugPrint("local user ${connection.localUid} joined");
          setState(() {
            _localUserJoined = true;
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          debugPrint("remote user $remoteUid joined");
          setState(() {
            _remoteUid = remoteUid;
          });
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          debugPrint("remote user $remoteUid left channel");
          setState(() {
            _remoteUid = null;
          });
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          debugPrint(
              '[onTokenPrivilegeWillExpire] connection: ${connection.toJson()}, token: $token');
        },
      ),
    );

    await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine.enableVideo();
    await _engine.startPreview();
  }

  joinSession() async {
    await _engine.joinChannelEx(
      token: token,
      connection: const RtcConnection(channelId: channel, localUid: 1000),
      options: const ChannelMediaOptions(
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
    _engine.setVideoEncoderConfiguration(const VideoEncoderConfiguration(
      dimensions:  VideoDimensions(width: 960, height: 720),
      frameRate: 30,
      bitrate: 2760,
    ));
  }

  void startScreenShare() async {
    if (_isScreenShared) return;
    print("Start share");

    await _engine.startScreenCapture(
        const ScreenCaptureParameters2(captureAudio: true, captureVideo: true));
    await _engine.startPreview(sourceType: VideoSourceType.videoSourceScreen);
    await _showRPSystemBroadcastPickerViewIfNeed();
    if (_localUserJoined) {
      _updateScreenShareChannelMediaOptions();
    }
  }

  Future<void> _showRPSystemBroadcastPickerViewIfNeed() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    await _iosScreenShareChannel
        .invokeMethod('showRPSystemBroadcastPickerView');
  }

  leaveSession() async {
    await _engine.stopScreenCapture();
    await _engine.leaveChannel();
    setState(() {
      _localUserJoined = false;
    });
  }

  Future<void> _updateScreenShareChannelMediaOptions() async {
    final shareShareUid = int.tryParse("1000");
    if (shareShareUid == null) return;
    await _engine.updateChannelMediaOptionsEx(
      options: const ChannelMediaOptions(
        publishScreenTrack: true,
        publishSecondaryScreenTrack: true,
        publishCameraTrack: false,
        publishMicrophoneTrack: false,
        publishScreenCaptureAudio: true,
        publishScreenCaptureVideo: true,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
      connection: RtcConnection(channelId: channel, localUid: shareShareUid),
    );
    setState(() {
      _isScreenShared = true;
    });
  }

  void stopScreenShare() async {
    if (!_isScreenShared) return;

    await _engine.stopScreenCapture();
    setState(() {
      _isScreenShared = false;
    });
  }

  @override
  void dispose() {
    super.dispose();

    _dispose();
  }

  Future<void> _dispose() async {
    await _engine.leaveChannel();
    await _engine.release();
  }

  // Create UI with local view and remote view
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agora Video Call'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: Center(
                  child: _remoteVideo(),
                ),
              ),
              TextButton(
                onPressed: _localUserJoined ? leaveSession : joinSession,
                child:
                    Text(_localUserJoined ? 'Leave Session' : 'Join Session'),
              ),
              TextButton(
                onPressed: _isScreenShared ? stopScreenShare : startScreenShare,
                child: Text(
                    _isScreenShared ? 'Stop ScreenShare' : 'Start ScreenShare'),
              )
            ],
          ),
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 100,
              height: 150,
              child: Center(
                child: _localUserJoined
                    ? AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _engine,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Display remote user's video
  Widget _remoteVideo() {
    if (_remoteUid != null) {
      return AgoraVideoView(
        controller: VideoViewController.remote(
          rtcEngine: _engine,
          canvas: VideoCanvas(uid: _remoteUid),
          connection: const RtcConnection(channelId: channel),
        ),
      );
    } else {
      return const Text(
        'Please wait for remote user to join',
        textAlign: TextAlign.center,
      );
    }
  }
}
