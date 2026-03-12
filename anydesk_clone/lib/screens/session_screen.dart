import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../services/signaling_service.dart';

class SessionScreen extends StatefulWidget {
  final String targetId;

  const SessionScreen({super.key, required this.targetId});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignalingService>().connectTo(widget.targetId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final signalingService = context.watch<SignalingService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Session: ${widget.targetId}'),
        actions: [
          if (signalingService.hasRemoteStream)
            const Padding(
              padding: EdgeInsets.only(right: 8.0),
              child: Center(
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Colors.green, size: 10),
                    SizedBox(width: 4),
                    Text('Connected', style: TextStyle(color: Colors.green, fontSize: 12)),
                  ],
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.redAccent),
            onPressed: () {
              signalingService.endSession();
              Navigator.pop(context);
            },
          )
        ],
      ),
      body: Stack(
        children: [
          // Video Stream or Loading indicator
          Center(
            child: signalingService.hasRemoteStream
                ? AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: RTCVideoView(
                        signalingService.remoteRenderer,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                        mirror: false,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.redAccent),
                      const SizedBox(height: 24),
                      Text(
                        'Waiting for remote screen...',
                        style: TextStyle(color: Colors.white54, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The remote user needs to accept and share their screen.',
                        style: TextStyle(color: Colors.white30, fontSize: 13),
                      ),
                    ],
                  ),
          ),
          // Input Overlay (captures clicks to send to remote) — only when stream is active
          if (signalingService.hasRemoteStream)
            Positioned.fill(
              child: GestureDetector(
                onTapDown: (details) {
                  print("Tapped at: ${details.localPosition}");
                  signalingService.sendCommand({
                    'action': 'move',
                    'x': details.localPosition.dx,
                    'y': details.localPosition.dy,
                  });
                  signalingService.sendCommand({
                    'action': 'click'
                  });
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
