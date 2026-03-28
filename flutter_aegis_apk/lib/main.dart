import 'dart:async';
import 'package:flutter/material.dart';
import 'core/theme/aegis_theme.dart';
import 'features/identity/identity_screen.dart';
import 'features/radar/radar_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/vault/vault_screen.dart';
import 'features/tunnels/tunnels_screen.dart';
import 'features/omni/omni_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'state/mesh_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AegisApp()));
}

class AegisApp extends StatelessWidget {
  const AegisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aegis',
      theme: AegisTheme.themeData,
      home: const AppRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppRouter extends ConsumerStatefulWidget {
  const AppRouter({super.key});

  @override
  ConsumerState<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends ConsumerState<AppRouter> {
  bool _initialized = false;
  String _ghostId = '';
  String _callsign = '';

  /// Called by IdentityScreen when the user taps "Connect to Mesh".
  void _handleInitializationComplete(String id, String callsign) {
    ref.read(meshProvider).setDeviceId(id, userCallsign: callsign);
    ref.read(meshProvider).startMesh();
    setState(() {
      _ghostId = id;
      _callsign = callsign;
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return IdentityScreen(onComplete: _handleInitializationComplete);
    }
    return MainHudScreen(ghostId: _ghostId, callsign: _callsign);
  }
}

class MainHudScreen extends ConsumerStatefulWidget {
  final String ghostId;
  final String callsign;

  const MainHudScreen({super.key, required this.ghostId, required this.callsign});

  @override
  ConsumerState<MainHudScreen> createState() => _MainHudScreenState();
}

class _MainHudScreenState extends ConsumerState<MainHudScreen> {
  int _currentIndex = 0;
  StreamSubscription? _notificationSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupNotificationListener();
    });
  }

  void _setupNotificationListener() {
    _notificationSub = ref.read(meshProvider).notificationStream.listen((data) {
      final String peerId = data['peerId'] as String? ?? '';
      final String name = data['senderName'] as String? ?? 'Ghost';
      final String text = data['text'] as String? ?? '';

      _showTacticalNotification(peerId, name, text);
    });
  }

  void _showTacticalNotification(String peerId, String name, String text) {
    if (!mounted) return;

    final isPublic = peerId == 'public';
    final label = isPublic ? 'PUBLIC FEED' : 'GHOST ALERT';
    final snippet = text.length > 50 ? '${text.substring(0, 47)}…' : text;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 70), // Show above bottom nav
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5)),
        ),
        content: Row(
          children: [
            Icon(
              isPublic ? Icons.rss_feed : Icons.security,
              size: 16,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label: $name',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snippet,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: Theme.of(context).primaryColor,
          onPressed: () {
            if (isPublic) {
              setState(() => _currentIndex = 2); // Switch to Omni Screen
            } else {
              _handleSelectPeer(context, peerId);
            }
          },
        ),
      ),
    );
  }

  void _handleSelectPeer(BuildContext context, String peerId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(peerId: peerId)),
    );
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    // Sync active chat state with MeshProvider for notifications
    final provider = ref.read(meshProvider);
    if (index == 2) {
      provider.activeChatPeerId = 'public';
    } else {
      // If we move away from public tab, and we weren't in a private chat, set it null
      if (provider.activeChatPeerId == 'public') {
        provider.activeChatPeerId = null;
      }
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.security, size: 12, color: Theme.of(context).primaryColor),
                const SizedBox(width: 4),
                const Text(
                  'AEGIS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2),
                ),
              ],
            ),
            Text(
              widget.callsign.isNotEmpty
                  ? '${widget.callsign}  •  ${widget.ghostId}'
                  : widget.ghostId,
              style: const TextStyle(fontSize: 8, color: Colors.white54, letterSpacing: 1),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: const [
                    Icon(Icons.wifi, size: 10, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('MESH-NET: ACTIVE', style: TextStyle(fontSize: 8)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: const [
                    Icon(Icons.bluetooth, size: 10, color: Colors.white70),
                    SizedBox(width: 4),
                    Text('BLE: ACTIVE', style: TextStyle(fontSize: 8)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const RadarScreen(),
          TunnelsScreen(
            onSelectPeer: (peer) => _handleSelectPeer(context, peer),
          ),
          const OmniScreen(),
          const VaultScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'HUD'),
          BottomNavigationBarItem(icon: Icon(Icons.link), label: 'TUNNELS'),
          BottomNavigationBarItem(icon: Icon(Icons.rss_feed), label: 'PUBLIC'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'VAULT'),
        ],
      ),
    );
  }
}
