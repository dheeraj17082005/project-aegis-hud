import 'package:flutter/material.dart';
import '../../services/secure_database.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  bool _deadManArmed = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Security Protocols', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2)),
            Text('VAULT & DATA MANAGEMENT', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Dead Man's Switch Section
          _buildSectionHeader(context, Icons.warning_amber, 'Volatile Memory Purge (Dead Man\'s Switch)', Colors.cyanAccent),
          const SizedBox(height: 16),
          // Simple visual representation of DeadMansSwitch
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3), width: 2),
              borderRadius: BorderRadius.circular(8),
              color: Colors.red.withValues(alpha: 0.05),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('DEAD MAN\'S SWITCH', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 2)),
                    SizedBox(height: 4),
                    Text('STATUS: ARMED', style: TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
                Switch(
                  value: _deadManArmed,
                  activeThumbColor: Colors.redAccent,
                  onChanged: (v) {
                    setState(() => _deadManArmed = v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildInfoCard('Wipe Condition', 'App Inactivity > 24H')),
              const SizedBox(width: 16),
              Expanded(child: _buildInfoCard('Purge Protocol', 'Prime (Full Wipe)')),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () async {
              await SecureDatabase().purgeAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TEST PURGE EXECUTED.')));
              }
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
            ),
            child: const Text('TEST AUTO-PURGE', style: TextStyle(fontSize: 10, letterSpacing: 2)),
          ),
          
          const SizedBox(height: 32),
          // Memory Status Section
          _buildSectionHeader(context, Icons.storage, 'Volatile Memory Status', Colors.cyanAccent),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
              border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('LOCAL STORAGE: ENCRYPTED', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('DATA RETENTION: VOLATILE', style: TextStyle(fontSize: 10, color: Colors.white54)),
                  ],
                ),
                Icon(Icons.lock, color: Theme.of(context).primaryColor.withValues(alpha: 0.6), size: 24),
              ],
            ),
          ),

          const SizedBox(height: 32),
          // Manual Purge Section
          _buildSectionHeader(context, Icons.delete_outline, 'Manual Purge Controls', Colors.redAccent),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () async {
              try {
                // Ensure initialized if required, or assuming initialization occurred in Main
                await SecureDatabase().purgeAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PURGE COMPLETE: All volatile data securely erased.')));
                }
              } catch (e) {
                // Fallback catch
                debugPrint('Purge Error: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
              foregroundColor: Colors.redAccent,
              side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: const Text('EXECUTE MANUAL PURGE (ALL CHATS)', style: TextStyle(letterSpacing: 2)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Histories Cleared (Mock)')));
                    debugPrint('Histories Cleared');
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white10)),
                  child: const Text('CLEAR HISTORIES', style: TextStyle(fontSize: 10, color: Colors.white70)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keys Rotated (Mock)')));
                    debugPrint('Keys Rotated');
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white10)),
                  child: const Text('ROTATE KEYS', style: TextStyle(fontSize: 10, color: Colors.white70)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),
          const Center(
            child: Text(
              'PROJECT AEGIS v0.9.4-BETA • SOVEREIGN MESH NETWORK',
              style: TextStyle(fontSize: 8, color: Colors.white24, letterSpacing: 4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: color)),
      ],
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white54)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
