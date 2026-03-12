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
  bool _hasAttemptedConnection = false;

  @override
  void initState() {
    super.initState();
    _hasAttemptedConnection = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignalingService>().connectTo(widget.targetId).then((_) {
        setState(() {
          _hasAttemptedConnection = true;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final signalingService = context.watch<SignalingService>();

    // If connection was attempted/active and then lost, navigate back
    if (_hasAttemptedConnection && !signalingService.isConnected && context.mounted) {
      Future.microtask(() {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }

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
                        key: ValueKey(signalingService.remoteRenderer.srcObject?.id ?? 'remote'),
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
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          signalingService.connectionStatus,
                          style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'The remote user needs to accept and share their screen.',
                        style: TextStyle(color: Colors.white30, fontSize: 13),
                      ),
                    ],
                  ),
          ),
          // Input Overlay (captures clicks to send to remote) — only when stream is active
          if (signalingService.hasRemoteStream)
            Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      onPanUpdate: (details) {
                        // Calculate normalized coordinates
                        double nx = details.localPosition.dx / constraints.maxWidth;
                        double ny = details.localPosition.dy / constraints.maxHeight;
                        
                        // Clamp to 0.0 - 1.0
                        nx = nx.clamp(0.0, 1.0);
                        ny = ny.clamp(0.0, 1.0);

                        signalingService.sendCommand({
                          'action': 'move',
                          'x': nx,
                          'y': ny,
                        });
                      },
                      onTapDown: (details) {
                        // Calculate normalized coordinates for click
                        double nx = details.localPosition.dx / constraints.maxWidth;
                        double ny = details.localPosition.dy / constraints.maxHeight;
                        
                        nx = nx.clamp(0.0, 1.0);
                        ny = ny.clamp(0.0, 1.0);

                        signalingService.sendCommand({
                          'action': 'move',
                          'x': nx,
                          'y': ny,
                        });
                        signalingService.sendCommand({
                          'action': 'click'
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
