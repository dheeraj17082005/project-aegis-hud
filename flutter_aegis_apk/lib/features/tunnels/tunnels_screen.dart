import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/mesh_provider.dart';

class TunnelsScreen extends ConsumerWidget {
  final Function(String) onSelectPeer;

  const TunnelsScreen({super.key, required this.onSelectPeer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mesh = ref.watch(meshProvider);
    final activePeers = mesh.activePeers;
    final primary = Theme.of(context).primaryColor;

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
                  Icon(Icons.link, size: 12, color: primary),
                  const SizedBox(width: 4),
                  Text('NODES: ${activePeers.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: activePeers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _PulseLogo(),
                  const SizedBox(height: 24),
                  const Text(
                    'TRANSMITTING BEACONS...',
                    style: TextStyle(color: Colors.white54, letterSpacing: 4, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Looking for nearby Ghosts...',
                    style: TextStyle(color: Colors.white24, fontSize: 12),
                  ),
                  const SizedBox(height: 32),
                  TextButton.icon(
                    onPressed: () => ref.read(meshProvider).startMesh(),
                    icon: Icon(Icons.refresh, size: 16, color: primary),
                    label: Text('RE-INITIALIZE RADIOS', style: TextStyle(color: primary, fontSize: 11, letterSpacing: 1)),
                  ),
                ],
              ),
            )
          : ListView(

              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              children: [
                ...activePeers.map((peer) {
                  final peerId = peer['peerId'] as String? ?? 'Unknown';
                  final source = peer['source'] as String? ?? 'lan';
                  final displayName = mesh.getDisplayName(peerId);
                  final unread = mesh.getUnreadCount(peerId);
                  final lastMsg = mesh.getLastMessage(peerId);

                  return _PeerTile(
                    peerId: peerId,
                    displayName: displayName,
                    source: source,
                    unreadCount: unread,
                    lastMessage: lastMsg,
                    onTap: () => onSelectPeer(peerId),
                  );
                }),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.radar, size: 14),
                  label: const Text('SCAN FOR NEW PEERS', style: TextStyle(letterSpacing: 2, fontSize: 10)),
                  onPressed: () async {
                    final ctx = context;
                    try {
                      await ref.read(meshProvider).startMesh();
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: const Text('Pulse transmitted — scanning...'),
                            backgroundColor: primary.withValues(alpha: 0.8),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Scan error: $e'), backgroundColor: Colors.redAccent),
                        );
                      }
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final String peerId;
  final String displayName;
  final String source;
  final int unreadCount;
  final Map<String, dynamic>? lastMessage;
  final VoidCallback onTap;

  const _PeerTile({
    required this.peerId,
    required this.displayName,
    required this.source,
    required this.unreadCount,
    required this.lastMessage,
    required this.onTap,
  });

  IconData get _sourceIcon {
    switch (source) {
      case 'ble':
        return Icons.bluetooth;
      case 'wifi_direct':
        return Icons.wifi_tethering;
      default:
        return Icons.lan;
    }
  }

  String get _sourceLabel {
    switch (source) {
      case 'ble':
        return 'BLE';
      case 'wifi_direct':
        return 'Wi-Fi Direct';
      default:
        return 'LAN';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final hasUnread = unreadCount > 0;
    final lastText = lastMessage?['message'] as String? ?? '';
    final lastTime = lastMessage?['time'] as String? ?? '';
    final lastSender = lastMessage?['sender'] as String? ?? '';
    final lastSenderLabel = lastSender == 'me' ? 'You: ' : '';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasUnread
                ? primary.withValues(alpha: 0.5)
                : primary.withValues(alpha: 0.2),
          ),
          color: hasUnread
              ? primary.withValues(alpha: 0.08)
              : primary.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Online indicator dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary,
                boxShadow: [
                  BoxShadow(color: primary.withValues(alpha: 0.8), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Name + message preview
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: TextStyle(
                            fontWeight: hasUnread ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastTime.isNotEmpty)
                        Text(
                          lastTime,
                          style: TextStyle(
                            fontSize: 9,
                            color: hasUnread ? primary : Colors.white30,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastText.isNotEmpty
                              ? '$lastSenderLabel$lastText'
                              : 'Tap to open encrypted tunnel',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasUnread ? Colors.white54 : Colors.white30,
                            fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Source badge
                      Row(
                        children: [
                          Icon(_sourceIcon, size: 9, color: Colors.white24),
                          const SizedBox(width: 2),
                          Text(
                            _sourceLabel,
                            style: const TextStyle(fontSize: 8, color: Colors.white24),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // Unread badge or chevron
            if (hasUnread)
              Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PulseLogo extends StatefulWidget {
  const _PulseLogo();

  @override
  State<_PulseLogo> createState() => _PulseLogoState();
}

class _PulseLogoState extends State<_PulseLogo> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              width: 100 * _controller.value,
              height: 100 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: primary.withOpacity(1 - _controller.value), width: 2),
              ),
            );
          },
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              width: 150 * _controller.value,
              height: 150 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: primary.withOpacity((1 - _controller.value) * 0.5), width: 1),
              ),
            );
          },
        ),
        Icon(Icons.radar, size: 48, color: primary),
      ],
    );
  }
}
