import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sodium/sodium.dart';

class CryptoService {
  late final Sodium _sodium;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _sodium = await SodiumInit.init();
      _initialized = true;
      debugPrint('Libsodium FFI Initialized Successfully.');
    } catch (e) {
      debugPrint('Failed to initialize Libsodium: $e');
      rethrow;
    }
  }

  /// Generates a sovereign Ed25519 keypair for identity and off-grid signing.
  KeyPair generateEd25519KeyPair() {
    _ensureInitialized();
    return _sodium.crypto.sign.keyPair();
  }

  /// Hashes the public key via SHA-256 to generate the GhostID.
  String generateGhostID(Uint8List publicKey) {
    final digest = sha256.convert(publicKey);
    // Return the SHA-256 hash as a hex string
    return digest.toString();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('CryptoService is not initialized. Call initialize() first.');
    }
  }
}
