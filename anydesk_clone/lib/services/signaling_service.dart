import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'signaling_url_stub.dart'
    if (dart.library.html) 'signaling_url_web.dart' as url_helper;

class SignalingService extends ChangeNotifier {
  WebSocketChannel? _channel;
  WebSocketChannel? _localPythonHostChannel;
  RTCDataChannel? _dataChannel;
  
  String _myId = "";
  String get myId => _myId;
  
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool isConnected = false;
  bool isHostMode = false;
  bool hasRemoteStream = false;
  String? _pendingOffer;
  String? _pendingOfferSender;
  
  String get signalingServerUrl => url_helper.getSignalingUrl();

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    final rng = Random.secure();
    _myId = (100000000 + rng.nextInt(900000000)).toString();
    notifyListeners();

    _connectSignalingServer();
    if (!kIsWeb) {
      _connectLocalPythonHost();
    }
  }

  void _connectLocalPythonHost() {
    try {
      _localPythonHostChannel = WebSocketChannel.connect(Uri.parse('ws://localhost:8081'));
      print("Connected to Python Host Script for OS Control.");
    } catch (e) {
      print("Could not connect to Python Host Script.");
    }
  }

  void _connectSignalingServer() {
    print("Connecting to signaling server: $signalingServerUrl");
    _channel = WebSocketChannel.connect(Uri.parse(signalingServerUrl));
    _channel!.stream.listen((message) {
      _handleMessage(jsonDecode(message));
    }, onDone: () {
      print('Signaling server disconnected');
    }, onError: (error) {
      print('Signaling server error: $error');
    });

    _send('register', {'id': _myId});
    print("Registered with ID: $_myId");
  }

  void _send(String type, Map<String, dynamic> data) {
    if (_channel != null) {
      data['type'] = type;
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _handleMessage(Map<String, dynamic> message) async {
    print("Received signaling message: ${message['type']}");
    switch (message['type']) {
      case 'offer':
        _pendingOffer = jsonEncode(message['data']);
        _pendingOfferSender = message['sender'];
        isHostMode = true;
        notifyListeners();
        break;
      case 'answer':
        print("Received answer, setting remote description...");
        final sdp = RTCSessionDescription(message['data']['sdp'], message['data']['type']);
        await peerConnection?.setRemoteDescription(sdp);
        print("Remote description set (answer).");
        break;
      case 'candidate':
        final candidate = RTCIceCandidate(
          message['data']['candidate'], 
          message['data']['sdpMid'], 
          message['data']['sdpMLineIndex']
        );
        await peerConnection?.addCandidate(candidate);
        break;
      case 'error':
        print("Signaling error: ${message['message']}");
        break;
      case 'end':
        print("Received end session command.");
        await endSession();
        break;
    }
  }

  /// Called from UI button press (user gesture) to accept the incoming connection.
  Future<void> acceptIncomingConnection() async {
    if (_pendingOffer == null || _pendingOfferSender == null) return;
    
    final offerData = jsonDecode(_pendingOffer!);
    final senderId = _pendingOfferSender!;
    final sdp = RTCSessionDescription(offerData['sdp'], offerData['type']);
    
    await _setupPeerConnection(senderId);

    // STEP 1: Share screen FIRST to get the tracks
    await shareScreen();
    print("Host: Screen shared, tracks added.");

    // STEP 2: Set the remote description (the offer from the caller)
    await peerConnection!.setRemoteDescription(sdp);
    print("Host: Remote description set (offer from caller).");

    // STEP 3: Create and send the answer
    RTCSessionDescription answer = await peerConnection!.createAnswer({
      'mandatory': {
        'OfferToReceiveAudio': false,
        'OfferToReceiveVideo': false, // Host sends video but doesn't receive
      }
    });
    await peerConnection!.setLocalDescription(answer);
    print("Host: Answer created and set.");
    print("Host: Answer SDP contains video: ${answer.sdp?.contains('m=video') ?? false}");

    _send('answer', {
      'target': senderId,
      'data': {
        'type': answer.type,
        'sdp': answer.sdp,
      }
    });

    isConnected = true;
    _pendingOffer = null;
    _pendingOfferSender = null;
    notifyListeners();
  }

  void _setRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    remoteRenderer.srcObject = stream;
    hasRemoteStream = true;
    
    // Log track info for debugging
    final videoTracks = stream.getVideoTracks();
    final audioTracks = stream.getAudioTracks();
    print("*** Remote stream set! Video tracks: ${videoTracks.length}, Audio tracks: ${audioTracks.length}");
    for (var track in videoTracks) {
      print("*** Video track: id=${track.id}, enabled=${track.enabled}, muted=${track.muted}");
      // Ensure track is enabled
      track.enabled = true;
    }
    
    notifyListeners();
  }

  Future<void> _setupPeerConnection(String targetId) async {
    final Map<String, dynamic> configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
      ]
    };

    peerConnection = await createPeerConnection(configuration);

    peerConnection!.onIceCandidate = (candidate) {
      _send('candidate', {
        'target': targetId,
        'data': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }
      });
    };

    peerConnection!.onTrack = (RTCTrackEvent event) {
      print("*** onTrack fired! streams: ${event.streams.length}, track kind: ${event.track.kind}, track id: ${event.track.id}");
      print("*** Track enabled: ${event.track.enabled}, muted: ${event.track.muted}");
      if (event.streams.isNotEmpty) {
        _setRemoteStream(event.streams[0]);
        print("*** Remote stream set on renderer via onTrack!");
      } else if (event.track.kind == 'video') {
        print("*** No streams in event, but got video track - waiting for onAddStream...");
      }
    };

    peerConnection!.onAddStream = (MediaStream stream) {
      print("*** onAddStream fired! stream id: ${stream.id}, tracks: ${stream.getTracks().length}");
      _setRemoteStream(stream);
      print("*** Remote stream set on renderer (via onAddStream)!");
    };

    peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      print("*** Connection state: $state");
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        print("*** Connection FAILED - may need to restart");
      }
    };

    peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      print("*** ICE connection state: $state");
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        print("*** ICE connected! Checking remote streams...");
        // Force refresh the renderer
        if (_remoteStream != null) {
          remoteRenderer.srcObject = _remoteStream;
          notifyListeners();
        }
      }
    };
    
    peerConnection!.onDataChannel = (RTCDataChannel channel) {
      print("*** onDataChannel received");
      _dataChannel = channel;
      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        if (!message.isBinary) {
          print("Received Command from Peer: ${message.text}");
          if (_localPythonHostChannel != null) {
            _localPythonHostChannel!.sink.add(message.text);
          }
        }
      };
    };
  }

  Future<void> sendCommand(Map<String, dynamic> command) async {
    if (_dataChannel != null && _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(command)));
    } else {
      print("DataChannel not open, state: ${_dataChannel?.state}");
    }
  }

  Future<void> connectTo(String targetId) async {
    await _setupPeerConnection(targetId);
    
    // Add a recvonly video transceiver BEFORE creating the offer.
    // This tells the SDP that we expect to RECEIVE video from the host.
    await peerConnection!.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    print("Client: Added recvonly video transceiver.");
    
    // Create data channel for control commands
    RTCDataChannelInit dataChannelDict = RTCDataChannelInit()..id = 1;
    _dataChannel = await peerConnection!.createDataChannel("control", dataChannelDict);
    _dataChannel!.onMessage = (RTCDataChannelMessage message) {
      print("Received (as initiator): ${message.text}");
      if (_localPythonHostChannel != null && !message.isBinary) {
        _localPythonHostChannel!.sink.add(message.text);
      }
    };
    _dataChannel!.onDataChannelState = (RTCDataChannelState state) {
      print("DataChannel state: $state");
    };
    
    // Create and send the offer
    RTCSessionDescription offer = await peerConnection!.createOffer({
      'mandatory': {
        'OfferToReceiveAudio': false,
        'OfferToReceiveVideo': true, // Client wants to receive video
      }
    });
    await peerConnection!.setLocalDescription(offer);
    print("Client: Offer created with video transceiver. SDP has video m= line.");
    
    _send('offer', {
      'target': targetId,
      'data': {
        'type': offer.type,
        'sdp': offer.sdp,
      }
    });

    isConnected = true;
    notifyListeners();
  }

  Future<void> shareScreen() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth': '1280',
          'minHeight': '720',
          'minFrameRate': '30',
        },
        'optional': [],
      }, 
    };

    try {
      if (kIsWeb) {
        if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
          throw Exception("Screen sharing is not supported on mobile web browsers.");
        }
        localStream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
      } else {
        // Desktop platforms (Windows, macOS, Linux)
        final sources = await desktopCapturer.getSources(types: [SourceType.Screen]);
        if (sources.isEmpty) {
          throw Exception("No screens found.");
        }
        
        final String sourceId = sources.first.id;
        
        MediaStream stream = await navigator.mediaDevices.getDisplayMedia({
          'audio': false,
          'video': {
            'deviceId': {'exact': sourceId},
            'mandatory': {'frameRate': 30.0}
          }
        });
        localStream = stream;
      }
      
      localRenderer.srcObject = localStream;
      
      final tracks = localStream!.getTracks();
      print("Got display media, tracks: ${tracks.length}");
      for (var track in tracks) {
        print("Display media track: kind=${track.kind}, id=${track.id}, enabled=${track.enabled}");
      }
      
      if (peerConnection != null && localStream != null) {
        for (var track in localStream!.getTracks()) {
          await peerConnection!.addTrack(track, localStream!);
          print("Added track: ${track.kind} to peer connection");
        }
        
        // Verify senders have tracks
        final senders = await peerConnection!.getSenders();
        for (var sender in senders) {
          print("Sender: track kind=${sender.track?.kind}, id=${sender.track?.id}");
        }
      }
      notifyListeners();
    } catch (e) {
      print("Error sharing screen: $e");
    }
  }

  Future<void> endSession() async {
    print("Ending session: Cleaning up resources.");
    
    // Notify peer
    if (isConnected && !isHostMode && _pendingOfferSender != null) {
      _send('end', {'target': _pendingOfferSender!});
    } else if (isConnected && isHostMode && _pendingOfferSender != null) {
      _send('end', {'target': _pendingOfferSender!});
    }

    // Close PeerConnection
    await peerConnection?.close();
    peerConnection = null;

    // Close DataChannel
    await _dataChannel?.close();
    _dataChannel = null;

    // Dispose Streams
    if (localStream != null) {
      for (var track in localStream!.getTracks()) {
        track.stop();
      }
      await localStream!.dispose();
      localStream = null;
    }
    
    if (_remoteStream != null) {
      for (var track in _remoteStream!.getTracks()) {
        track.stop();
      }
      await _remoteStream!.dispose();
      _remoteStream = null;
    }

    // Reset Renderers
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    // Reset State
    isConnected = false;
    isHostMode = false;
    hasRemoteStream = false;
    _pendingOffer = null;
    _pendingOfferSender = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    localRenderer.dispose();
    remoteRenderer.dispose();
    peerConnection?.close();
    localStream?.dispose();
    _remoteStream?.dispose();
    super.dispose();
  }
}
