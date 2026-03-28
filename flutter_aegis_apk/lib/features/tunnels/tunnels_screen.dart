import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/mesh_provider.dart';

class TunnelsScreen extends ConsumerWidget {
  final Function(String) onSelectPeer;

  const TunnelsScreen({super.key, required this.onSelectPeer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePeers = ref.watch(meshProvider).activePeers;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Secure P2P Channels', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2)),
            Text('PRIVATE TUNNELS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Icon(Icons.link, size: 12, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 4),
                  Text('CONNECTIONS: ${activePeers.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: activePeers.isEmpty
          ? const Center(child: Text('Searching for Ghosts...', style: TextStyle(color: Colors.white54, letterSpacing: 2)))
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...activePeers.map((tunnel) => InkWell(
                onTap: () => onSelectPeer(tunnel['peerId'] as String? ?? 'Unknown'),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).primaryColor,
                          boxShadow: [BoxShadow(color: Theme.of(context).primaryColor.withValues(alpha: 0.8), blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tunnel['peerId'] as String? ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.security, size: 10, color: Colors.white30),
                                const SizedBox(width: 4),
                                const Text('DOUBLE RATCHET ACTIVE • ', style: TextStyle(fontSize: 8, color: Colors.white30)),
                                const Text('NOW', style: TextStyle(fontSize: 8, color: Colors.white30)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.4), style: BorderStyle.none),
            ),
            child: OutlinedButton(
              onPressed: () async {
                try {
                  await ref.read(meshProvider).startMesh();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scanning for peers... (Pulse Transmitted)')));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan Error: $e'), backgroundColor: Colors.redAccent));
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3), style: BorderStyle.solid),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: const Text('SCAN FOR NEW PEERS', style: TextStyle(letterSpacing: 2, fontSize: 10)),
            ),
          )
        ],
      ),
    );
  }
}
