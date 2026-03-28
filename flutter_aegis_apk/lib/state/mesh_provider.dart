import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mesh_channel_service.dart';

final meshProvider = ChangeNotifierProvider<MeshProvider>((ref) => MeshProvider());

class MeshProvider extends ChangeNotifier {
  final MeshChannelService _channelService;

  List<Map<String, dynamic>> _activePeers = [];
  final List<Map<String, dynamic>> _publicMessages = [];
  final Map<String, List<Map<String, dynamic>>> _privateMessages = {};

  StreamSubscription? _peersSub;
  StreamSubscription? _messagesSub;

  String deviceId = "Unknown";
  bool debugMode = false;

  void setDeviceId(String id) {
    deviceId = id;
    debugPrint('MeshProvider Ghost ID injected: $deviceId');
    notifyListeners();
  }

  void injectFakePeer() {
    _activePeers.add({
      'peerId': 'ghost_DEBUG_99',
      'deviceName': 'ghost_DEBUG_99',
      'status': 'Online'
    });
    notifyListeners();
  }

  MeshProvider({MeshChannelService? channelService})
      : _channelService = channelService ?? MeshChannelService() {
    _initSubscriptions();
    // Auto-start LAN beacon discovery immediately
    _autoStartLan();
  }

  Future<void> _autoStartLan() async {
    await Future.delayed(const Duration(seconds: 1)); // Let event channel attach
    try {
      await _channelService.startLanDiscovery();
      debugPrint('Auto-started LAN Beacon Discovery.');
    } catch (e) {
      debugPrint('Auto-start LAN failed (will retry on manual scan): $e');
    }
  }

  List<Map<String, dynamic>> get activePeers {
    // Peers are now populated universally by native code (LAN, Wi-Fi Direct, and BLE)
    return List<Map<String, dynamic>>.from(_activePeers);
  }
  
  List<Map<String, dynamic>> get publicMessages => _publicMessages;
  
  List<Map<String, dynamic>> getPrivateMessages(String peerId) {
    return _privateMessages[peerId] ?? [];
  }

  void _initSubscriptions() {
    _peersSub = _channelService.peersStream.listen((peers) {
      _activePeers = peers;
      notifyListeners();
    });

    _messagesSub = _channelService.messagesStream.listen((message) {
      final String rawMsg = message['message'] as String? ?? '';
      final String senderIp = message['sender'] as String? ?? '';
      
      try {
        final decoded = jsonDecode(rawMsg) as Map<String, dynamic>;
        final String type = decoded['type'] as String? ?? 'public';
        final String text = decoded['text'] as String? ?? '';
        final String senderId = decoded['senderId'] as String? ?? senderIp;
        final String toId = decoded['to'] as String? ?? '';

        if (senderId == deviceId) return;

        final processedMsg = {
          'message': text,
          'sender': senderId,
          'time': '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}'
        };

        if (type == 'private' && toId.isNotEmpty) {
           if (toId == deviceId) {
             _privateMessages.putIfAbsent(senderId, () => []);
             _privateMessages[senderId]!.insert(0, processedMsg);
             notifyListeners();
           }
        } else {
           _publicMessages.insert(0, processedMsg);
           notifyListeners();
        }
      } catch (e) {
        _publicMessages.insert(0, message);
        notifyListeners();
      }
    });
  }

  Future<void> startMesh() async {
    try {
      await _channelService.startLanDiscovery();
      debugPrint('LAN Beacon Discovery active.');
    } catch (e) {
      debugPrint('LAN Discovery error (non-fatal): $e');
    }

    try {
      final success = await _channelService.startDiscovery();
      if (success) {
        debugPrint('Wi-Fi Direct Discovery started.');
      } else {
        debugPrint('Wi-Fi Direct unavailable.');
      }
    } catch (e) {
      debugPrint('Wi-Fi Direct error (non-fatal): $e');
    }

    // 4. Start isolated custom Native BLE GATT bridge
    try {
      await _channelService.startBle();
      debugPrint('Custom Native BLE GATT started.');
    } catch (e) {
      debugPrint('Native BLE GATT error: $e');
    }
  }

  Future<void> stopMesh() async {
    final success = await _channelService.stopDiscovery();
    await _channelService.stopBle();
    if (success) {
      debugPrint('Mesh Discovery Stopped.');
    } else {
      debugPrint('Failed to stop natively.');
    }
  }

  Future<void> broadcastPublicMessage(String text) async {
    final payload = jsonEncode({
      "type": "public",
      "text": text,
      "senderId": deviceId,
    });
    
    // Broadcast via Native UDP
    final success = await _channelService.broadcastMessage(payload);
    if (!success) debugPrint('Warning: Message failed to transmit natively via UDP.');

    // Broadcast via custom BLE bridge
    await _channelService.sendBleMessage(payload);
  }

  Future<void> sendPrivateMessage(String toId, String text) async {
    final payload = jsonEncode({
      "type": "private",
      "to": toId,
      "text": text,
      "senderId": deviceId,
    });
    
    // Save locally
    _privateMessages.putIfAbsent(toId, () => []);
    _privateMessages[toId]!.insert(0, {
       'message': text,
       'sender': 'me',
       'time': '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}'
    });
    notifyListeners();

    // Send targeted message via Native UDP socket
    final success = await _channelService.sendMessage(toId, payload);
    if (!success) debugPrint('Warning: Private Message failed to transmit natively via UDP to $toId.');

    // Broadcast/Send via custom BLE bridge
    await _channelService.sendBleMessage(payload);
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _messagesSub?.cancel();
    _channelService.dispose();
    super.dispose();
  }
}
