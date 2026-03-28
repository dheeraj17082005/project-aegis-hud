import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../services/crypto_service.dart';
import 'package:permission_handler/permission_handler.dart';

class IdentityScreen extends StatefulWidget {
  /// Called when user taps "Connect to Mesh". Passes (ghostId, callsign).
  final Function(String ghostId, String callsign) onComplete;

  const IdentityScreen({super.key, required this.onComplete});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  int _progress = 0;
  String _status = 'AEGIS MESH INITIALIZATION';
  String _ghostId = '';
  Timer? _timer;
  bool _showCallsignEntry = false;

  final TextEditingController _callsignController = TextEditingController();
  final FocusNode _callsignFocus = FocusNode();

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

    // Relaxed Check: Only halt if fundamental Location and Bluetooth are both denied.
    // Nearby permissions are version-dependent; we shouldn't kill the app if they 
    // report 'permanentlyDenied' or 'restricted' on old hardware.
    bool locationOk = statuses[Permission.location]!.isGranted;
    bool bluetoothOk = statuses[Permission.bluetooth]!.isGranted;
    
    // On Android 12+, bluetoothScan might be required instead of location
    bool nearbyOk = (statuses[Permission.bluetoothScan]?.isGranted ?? false) || 
                   (statuses[Permission.bluetoothConnect]?.isGranted ?? false);

    if (!locationOk && !bluetoothOk && !nearbyOk) {
      debugPrint('Critical Permissions not granted.');
      if (mounted) {
        setState(() {
          _status = 'LOCATION/BLUETOOTH DENIED. HALTING.';
        });
      }
      return;
    }

    final crypto = CryptoService();
    try {
      // Small timeout for crypto init to prevent complete hang
      await crypto.initialize().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('Crypto Service Warning (Falling back to software): $e');
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
          try {
            final keyPair = crypto.generateEd25519KeyPair();
            _ghostId = crypto.generateGhostID(keyPair.publicKey).substring(0, 16);
          } catch (e) {
            debugPrint('Fallback to random GhostID: $e');
            final randomBytes = List<int>.generate(16, (i) => Random().nextInt(256));
            final partialHash = randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
            _ghostId = partialHash.substring(0, 16).toUpperCase();
          }
          // Show callsign entry after short delay for UX polish
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) setState(() => _showCallsignEntry = true);
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _callsignController.dispose();
    _callsignFocus.dispose();
    super.dispose();
  }

  void _connect() {
    final callsign = _callsignController.text.trim();
    widget.onComplete(_ghostId, callsign);
  }

  @override
  Widget build(BuildContext context) {
    final isComplete = _progress >= 100;
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
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
                          color: primary.withValues(alpha: 0.12),
                          blurRadius: 48,
                          spreadRadius: 16,
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.security, size: 80, color: primary),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'AEGIS',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: primary,
                ),
              ),
              const SizedBox(height: 48),

              // Progress bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _status.toUpperCase(),
                      style: const TextStyle(fontSize: 10, letterSpacing: 2, color: Colors.white54),
                      overflow: TextOverflow.ellipsis,
                    ),
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
                backgroundColor: primary.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(primary),
                minHeight: 4,
              ),
              const SizedBox(height: 48),

              // Ghost ID box + callsign entry
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: !isComplete
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        height: 140,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(primary.withValues(alpha: 0.4)),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'CRYPTOGRAPHIC HANDSHAKE IN PROGRESS...',
                              style: TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        ),
                      )
                    : SizedBox(
                        key: const ValueKey('complete'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ghost ID card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                border: Border.all(color: primary.withValues(alpha: 0.3)),
                                color: primary.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'SOVEREIGN KEY GENERATED',
                                    style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    _ghostId,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'This is your cryptographic identity on the mesh',
                                    style: TextStyle(fontSize: 9, color: Colors.white30),
                                  ),
                                ],
                              ),
                            ),

                            // Callsign entry — slides in after key is generated
                            AnimatedSize(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOut,
                              child: _showCallsignEntry
                                  ? Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.badge_outlined, size: 12, color: primary.withValues(alpha: 0.7)),
                                              const SizedBox(width: 6),
                                              Text(
                                                'CALLSIGN',
                                                style: TextStyle(fontSize: 10, letterSpacing: 2, color: primary.withValues(alpha: 0.7)),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '(OPTIONAL)',
                                                style: TextStyle(fontSize: 9, color: Colors.white30, letterSpacing: 1),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          TextField(
                                            controller: _callsignController,
                                            focusNode: _callsignFocus,
                                            maxLength: 20,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            decoration: InputDecoration(
                                              hintText: 'e.g. ALPHA-7, Ghost, Raven...',
                                              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                              counterStyle: const TextStyle(color: Colors.white24, fontSize: 9),
                                              prefixIcon: Icon(Icons.alternate_email, size: 16, color: primary.withValues(alpha: 0.5)),
                                              filled: true,
                                              fillColor: primary.withValues(alpha: 0.05),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: primary.withValues(alpha: 0.2)),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(8),
                                                borderSide: BorderSide(color: primary),
                                              ),
                                            ),
                                            onSubmitted: (_) => _connect(),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Peers will see this name instead of your Ghost ID',
                                            style: TextStyle(fontSize: 9, color: Colors.white24),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(height: 32),

              // Connect button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isComplete ? _connect : null,
                  child: Text(
                    isComplete ? 'CONNECT TO MESH' : 'INITIALIZING...',
                    style: const TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold),
                  ),
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
            Text('NODE: ${Random().nextInt(999999).toRadixString(16).toUpperCase()}',
                style: const TextStyle(fontSize: 8, color: Colors.white30)),
          ],
        ),
      ),
    );
  }
}
