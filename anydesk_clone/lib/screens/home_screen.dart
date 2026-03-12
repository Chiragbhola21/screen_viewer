import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/signaling_service.dart';
import 'session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _remoteIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SignalingService>().init();
    });
  }

  void _connectToRemote() {
    final remoteId = _remoteIdController.text.trim();
    if (remoteId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SessionScreen(targetId: remoteId),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final signalingService = context.watch<SignalingService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AnyDesk Clone', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {},
          )
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 500) {
                    // Mobile: stack vertically
                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildThisDeskPanel(signalingService),
                          Container(height: 1, color: Colors.white12),
                          _buildRemoteDeskPanel(),
                        ],
                      ),
                    );
                  }
                  // Desktop/Web: side by side
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildThisDeskPanel(signalingService)),
                      Container(width: 1, color: Colors.white12),
                      Expanded(child: _buildRemoteDeskPanel()),
                    ],
                  );
                },
              ),
            ),
          ),
          // Incoming connection overlay
          if (signalingService.isHostMode && !signalingService.isConnected)
            _buildIncomingConnectionOverlay(signalingService),
        ],
      ),
    );
  }

  Widget _buildIncomingConnectionOverlay(SignalingService signalingService) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Card(
          color: const Color(0xFF2D2D30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.screen_share, size: 64, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Incoming Connection Request',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A remote device wants to view and control your screen.\nYou will be asked to select which screen to share.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        // Decline
                        signalingService.isHostMode = false;
                        signalingService.notifyListeners();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[700],
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Decline', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          await signalingService.acceptIncomingConnection();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: ${e.toString()}'),
                                backgroundColor: Colors.red,
                                duration: const Duration(seconds: 5),
                              ),
                            );
                            signalingService.isHostMode = false;
                            signalingService.notifyListeners();
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Accept & Share Screen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThisDeskPanel(SignalingService signalingService) {
    return Container(
      padding: const EdgeInsets.all(32.0),
      color: const Color(0xFF1E1E1E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Desk',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    signalingService.myId.isEmpty ? "Generating..." : signalingService.myId,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.redAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white54),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: signalingService.myId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ID copied to clipboard!')),
                    );
                  },
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Share this ID to allow remote access to your device.',
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteDeskPanel() {
    return Container(
      padding: const EdgeInsets.all(32.0),
      color: const Color(0xFF1E1E1E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remote Desk',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              children: [
                const Icon(Icons.monitor, color: Colors.white54),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _remoteIdController,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Enter Remote ID',
                      hintStyle: TextStyle(color: Colors.white24),
                      border: InputBorder.none,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _connectToRemote,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
