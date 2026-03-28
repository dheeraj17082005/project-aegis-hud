import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

class SecureDatabase {
  static const String _dbName = 'aegis_vault.db';
  Database? _database;

  /// Initializes the SQLCipher AES-256 encrypted database
  /// [encryptionKey] derived from biometrics or user PIN
  Future<void> initializeVault(String encryptionKey) async {
    if (_database != null) return;

    final Directory docDir = await getApplicationDocumentsDirectory();
    final String path = join(docDir.path, _dbName);

    _database = await openDatabase(
      path,
      password: encryptionKey,
      version: 1,
      onCreate: (Database db, int version) async {
        // Table for the master private key
        await db.execute('''
          CREATE TABLE Identity (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            privateKey TEXT NOT NULL
          )
        ''');

        // Table for active Double Ratchet sessions
        await db.execute('''
          CREATE TABLE RatchetSessions (
            peerId TEXT PRIMARY KEY,
            sessionState TEXT NOT NULL,
            lastUpdated INTEGER NOT NULL
          )
        ''');
      },
    );

    debugPrint('Secure Vault Initialized.');
  }

  /// Store the master private key
  Future<void> storePrivateKey(String privateKeyHex) async {
    _ensureInitialized();
    await _database!.insert(
      'Identity',
      {'id': 1, 'privateKey': privateKeyHex},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve the master private key
  Future<String?> getPrivateKey() async {
    _ensureInitialized();
    final List<Map<String, dynamic>> maps = await _database!.query('Identity', where: 'id = ?', whereArgs: [1]);
    if (maps.isNotEmpty) {
      return maps.first['privateKey'] as String;
    }
    return null;
  }

  /// Store a Double Ratchet session state
  Future<void> saveRatchetSession(String peerId, String sessionStateHex) async {
    _ensureInitialized();
    await _database!.insert(
      'RatchetSessions',
      {
        'peerId': peerId,
        'sessionState': sessionStateHex,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve an active Double Ratchet session state
  Future<String?> getRatchetSession(String peerId) async {
    _ensureInitialized();
    final List<Map<String, dynamic>> maps = await _database!.query('RatchetSessions', where: 'peerId = ?', whereArgs: [peerId]);
    if (maps.isNotEmpty) {
      return maps.first['sessionState'] as String;
    }
    return null;
  }

  /// DEAD MAN'S SWITCH: Purge All
  /// Securely closes the UI database and entirely deletes the SQLCipher file.
  Future<void> purgeAll() async {
    _ensureInitialized();
    debugPrint('INITIATING DEAD MAN SWITCH: PURGE ALL');
    
    // Close the connection
    await _database!.close();
    _database = null;

    // Delete the database file securely
    final Directory docDir = await getApplicationDocumentsDirectory();
    final String path = join(docDir.path, _dbName);
    
    final file = File(path);
    if (await file.exists()) {
      // Overwrite file bytes for secure deletion before unlink
      final raf = await file.open(mode: FileMode.write);
      final size = await raf.length();
      final zeros = List<int>.filled(size > 0 ? size : 1024, 0);
      await raf.writeFrom(zeros);
      await raf.close();

      await deleteDatabase(path);
      debugPrint('Vault securely purged.');
    }
  }

  void _ensureInitialized() {
    if (_database == null) {
      throw StateError('SecureDatabase is not initialized. Call initializeVault() first with the encryption key.');
    }
  }
}
