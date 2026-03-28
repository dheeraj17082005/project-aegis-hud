import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/crypto_service.dart';
import 'package:permission_handler/permission_handler.dart';

class IdentityScreen extends StatefulWidget {
  final Function(String) onComplete;

  const IdentityScreen({super.key, required this.onComplete});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  int _progress = 0;
  String _status = 'AEGIS MESH INITIALIZATION';
  String _ghostId = '';
  Timer? _timer;

  final List<Map<String, dynamic>> _steps = [
    {'p': 20, 's': 'Establishing Sovereign Identity (X3DH)'},
    {'p': 50, 's': 'Generating Ephemeral Keys'},
    {'p': 80, 's': 'Local Node Active'},
    {'p': 100, 's': 'Sovereign Identity Verified'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInitialization();
    });
  }

  void _startInitialization() async {
    final statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);
    if (!allGranted) {
      debugPrint('Permissions not granted.');
      setState(() {
        _status = 'PERMISSIONS DECLINED. HALTING.';
      });
      return;
    }

    final crypto = CryptoService();
    try {
      await crypto.initialize();
    } catch (e) {
      debugPrint("Crypto Init Error: $e");
    }

    _timer = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted) return;
      setState(() {
        _progress++;
        final step = _steps.reversed.firstWhere(
          (s) => _progress >= s['p'],
          orElse: () => _steps.first,
        );
        _status = step['s'];

        if (_progress >= 100) {
          _progress = 100;
          _timer?.cancel();
          final keyPair = crypto.generateEd25519KeyPair();
          _ghostId = crypto.generateGhostID(keyPair.publicKey).substring(0, 16);
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isComplete = _progress >= 100;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Shield Icon (using Icons.security for now to avoid needing lucide package in this basic mock)
              Stack(
                alignment: Alignment.center,
                children: [
                   Container(
                     width: 120,
                     height: 120,
                     decoration: BoxDecoration(
                       shape: BoxShape.circle,
                       boxShadow: [
                         BoxShadow(
                           color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                           blurRadius: 40,
                           spreadRadius: 10,
                         )
                       ]
                     ),
                   ),
                   Icon(
                    Icons.security,
                    size: 80,
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'PROJECT AEGIS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 48),

              // Progress Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _status.toUpperCase(),
                    style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54),
                  ),
                  Text(
                    '$_progress%',
                    style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                minHeight: 4,
              ),
              const SizedBox(height: 48),

              // Status Box
              SizedBox(
                height: 120,
                child: Center(
                  child: !isComplete
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(context).primaryColor.withValues(alpha: 0.4),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'CRYPTOGRAPHIC HANDSHAKE IN PROGRESS...',
                              style: TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('SOVEREIGN KEY GENERATED', style: TextStyle(fontSize: 10, color: Colors.white54)),
                              const SizedBox(height: 8),
                              Text(
                                _ghostId,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),

              // Connect Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isComplete ? () => widget.onComplete(_ghostId) : null,
                  child: const Text('CONNECT TO MESH', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const Text('X3DH PROTOCOL', style: TextStyle(fontSize: 8, color: Colors.white30)),
            const Text('ED25519', style: TextStyle(fontSize: 8, color: Colors.white30)),
            Text('NODE_ID: ${Random().nextInt(999999).toRadixString(16).toUpperCase()}', style: const TextStyle(fontSize: 8, color: Colors.white30)),
          ],
        ),
      ),
    );
  }
}
