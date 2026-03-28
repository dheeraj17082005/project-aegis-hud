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
      title: 'Project Aegis HUD',
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

  void _handleInitializationComplete(String id) {
    ref.read(meshProvider).setDeviceId(id);
    ref.read(meshProvider).startMesh();
    setState(() {
      _ghostId = id;
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return IdentityScreen(onComplete: _handleInitializationComplete);
    }
    return MainHudScreen(ghostId: _ghostId);
  }
}

class MainHudScreen extends StatefulWidget {
  final String ghostId;

  const MainHudScreen({super.key, required this.ghostId});

  @override
  State<MainHudScreen> createState() => _MainHudScreenState();
}

class _MainHudScreenState extends State<MainHudScreen> {
  int _currentIndex = 0;

  void _handleSelectPeer(BuildContext context, String peer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(peerId: peer)),
    );
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
                Icon(
                  Icons.security,
                  size: 12,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 4),
                const Text(
                  'PROJECT AEGIS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
            Text(
              'ID: ${widget.ghostId}',
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white54,
                letterSpacing: 1,
              ),
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
                  children: [
                    const Icon(Icons.wifi, size: 10, color: Colors.white70),
                    const SizedBox(width: 4),
                    const Text(
                      'MESH-NET: ACTIVE',
                      style: TextStyle(fontSize: 8),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.battery_charging_full,
                      size: 10,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    const Text('PWR: 84%', style: TextStyle(fontSize: 8)),
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
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.radar), label: 'HUD'),
          BottomNavigationBarItem(
            icon: Icon(Icons.link),
            label: 'PRIVATE TUNNEL',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.rss_feed),
            label: 'PUBLIC TUNNEL',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'VAULT'),
        ],
      ),
    );
  }
}
