import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mesh_channel_service.dart';

final meshProvider = ChangeNotifierProvider<MeshProvider>((ref) => MeshProvider());

/// How long public messages are kept before auto-delete.
const Duration kPublicMessageTtl = Duration(hours: 1);

/// How long private messages are kept before auto-delete.
const Duration kPrivateMessageTtl = Duration(hours: 24);

/// How often the auto-delete sweep runs.
const Duration kAutoDeleteInterval = Duration(minutes: 5);

enum MessageStatus { sending, sent, delivered, failed }

class MeshProvider extends ChangeNotifier {
  final MeshChannelService _channelService;

  List<Map<String, dynamic>> _activePeers = [];
  final List<Map<String, dynamic>> _publicMessages = [];
  final Map<String, List<Map<String, dynamic>>> _privateMessages = {};

  /// Peer display names: peerId → callsign (or model).
  final Map<String, String> peerNames = {};

  /// Unread counts per peer — used for tunnel list badges.
  final Map<String, int> _unreadCounts = {};

  /// Which chat is currently open (suppresses unread increment).
  String? activeChatPeerId;

  /// Recently seen message IDs — for deduplication.
  final Set<String> _seenMessageIds = {};

  StreamSubscription? _peersSub;
  StreamSubscription? _messagesSub;
  Timer? _autoDeleteTimer;

  /// Internal stream for in-app notifications.
  final StreamController<Map<String, dynamic>> _notificationController = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of in-app notifications for background messages.
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;

  /// The native ANDROID_ID — used for message routing. Must match what's in the beacon.
  String deviceId = 'Unknown';
  /// The crypto Ghost ID — used for display only.
  String ghostId = '';
  String callsign = '';

  // ─── Init ─────────────────────────────────────────────────────────────────

  MeshProvider({MeshChannelService? channelService})
      : _channelService = channelService ?? MeshChannelService() {
    _initSubscriptions();
    _autoStartLan();
    _startAutoDelete();
    _fetchNativeDeviceId();
  }

  /// Fetch the native ANDROID_ID so we use the same identity as the beacon.
  Future<void> _fetchNativeDeviceId() async {
    await Future.delayed(const Duration(milliseconds: 500)); // Let engine attach
    try {
      final nativeId = await _channelService.getDeviceId();
      if (nativeId.isNotEmpty) {
        deviceId = nativeId;
        debugPrint('MeshProvider: deviceId synced from native → $deviceId');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to fetch native deviceId: $e');
    }
  }

  void setDeviceId(String cryptoGhostId, {String userCallsign = ''}) {
    // ghostId is the crypto identity for display
    ghostId = cryptoGhostId;
    callsign = userCallsign;
    debugPrint('MeshProvider → ghostId: $ghostId  callsign: "$callsign"  routing deviceId: $deviceId');
    if (userCallsign.isNotEmpty) {
      _channelService.setCallsign(userCallsign).catchError((e) {
        debugPrint('setCallsign error: $e');
        return false;
      });
    }
    // Re-fetch native ID in case it wasn't ready during construction
    _fetchNativeDeviceId();
    notifyListeners();
  }

  Future<void> _autoStartLan() async {
    await Future.delayed(const Duration(seconds: 1));
    try {
      await _channelService.startLanDiscovery();
      debugPrint('LAN Beacon auto-started.');
    } catch (e) {
      debugPrint('Auto-start LAN failed: $e');
    }
  }

  // ─── Auto-delete ──────────────────────────────────────────────────────────

  void _startAutoDelete() {
    _autoDeleteTimer = Timer.periodic(kAutoDeleteInterval, (_) => _sweepOldMessages());
  }

  void _sweepOldMessages() {
    final now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;

    final publicTtl = kPublicMessageTtl.inMilliseconds;
    final before1 = _publicMessages.length;
    _publicMessages.removeWhere((m) {
      final ts = m['epochMs'] as int? ?? 0;
      return ts > 0 && (now - ts) > publicTtl;
    });
    if (_publicMessages.length != before1) changed = true;

    final privateTtl = kPrivateMessageTtl.inMilliseconds;
    for (final peerId in _privateMessages.keys) {
      final before2 = _privateMessages[peerId]!.length;
      _privateMessages[peerId]!.removeWhere((m) {
        final ts = m['epochMs'] as int? ?? 0;
        return ts > 0 && (now - ts) > privateTtl;
      });
      if (_privateMessages[peerId]!.length != before2) changed = true;
    }

    // Prune old message IDs (keep last 500 to prevent memory leak)
    if (_seenMessageIds.length > 500) {
      final excess = _seenMessageIds.length - 500;
      _seenMessageIds.toList().sublist(0, excess).forEach(_seenMessageIds.remove);
    }

    if (changed) {
      debugPrint('Auto-delete: swept old messages.');
      notifyListeners();
    }
  }

  // ─── Accessors ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get activePeers =>
      List<Map<String, dynamic>>.from(_activePeers);

  List<Map<String, dynamic>> get publicMessages => _publicMessages;

  List<Map<String, dynamic>> getPrivateMessages(String peerId) =>
      _privateMessages[peerId] ?? [];

  String getDisplayName(String peerId) {
    if (peerId == 'me') return 'Me';
    final name = peerNames[peerId];
    if (name != null && name.isNotEmpty) return name;
    return peerId.length > 12 ? '${peerId.substring(0, 12)}…' : peerId;
  }

  int getUnreadCount(String peerId) => _unreadCounts[peerId] ?? 0;

  void markAsRead(String peerId) {
    if ((_unreadCounts[peerId] ?? 0) > 0) {
      _unreadCounts[peerId] = 0;
      notifyListeners();
    }
  }

  Map<String, dynamic>? getLastMessage(String peerId) {
    final msgs = _privateMessages[peerId];
    if (msgs == null || msgs.isEmpty) return null;
    return msgs.first;
  }

  // ─── Event subscriptions ──────────────────────────────────────────────────

  void _initSubscriptions() {
    _peersSub = _channelService.peersStream.listen((peers) {
      _activePeers = peers;
      for (final peer in peers) {
        final id = peer['peerId'] as String? ?? '';
        final name = peer['deviceName'] as String? ?? '';
        if (id.isNotEmpty && name.isNotEmpty) peerNames[id] = name;
      }
      notifyListeners();
    });

    _messagesSub = _channelService.messagesStream.listen((message) {
      final String rawMsg = message['message'] as String? ?? '';
      final String senderIp = message['sender'] as String? ?? '';

      try {
        final decoded = jsonDecode(rawMsg) as Map<String, dynamic>;
        final String msgId          = decoded['id'] as String? ?? decoded['msgId'] as String? ?? '';
        final String type           = decoded['type'] as String? ?? 'TEXT';
        final String senderId       = decoded['senderId'] as String? ?? senderIp;
        final String senderCallsign = decoded['senderCallsign'] as String? ?? '';
        final String payload        = decoded['payload'] as String? ?? decoded['text'] as String? ?? '';
        final String toId           = decoded['to'] as String? ?? '';
        // ignore: unused_local_variable
        final int timestamp         = decoded['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;

        // ── Drop our OWN echoed messages ──
        if (senderId == deviceId) return;

        // ── Deduplicate: skip if we already processed this exact message (unless it's an ACK) ──
        if (msgId.isNotEmpty && type != 'ACK') {
          if (_seenMessageIds.contains(msgId)) return;
          _seenMessageIds.add(msgId);
        }

        // Cache sender's callsign
        if (senderCallsign.isNotEmpty) peerNames[senderId] = senderCallsign;

        if (type == 'ACK') {
          // Handle acknowledgment
          _handleAck(senderId, msgId);
          return;
        }

        if (type == 'PING') {
          // Automatic response to PING
          _sendAck(senderId, msgId);
          return;
        }

        // Process message (TEXT)
        final epochMs = DateTime.now().millisecondsSinceEpoch;
        final processedMsg = {
          'id':         msgId,
          'message':    payload,
          'sender':     senderId,
          'senderName': senderCallsign.isNotEmpty ? senderCallsign : getDisplayName(senderId),
          'time':       _nowLabel(),
          'epochMs':    epochMs,
          'status':     MessageStatus.delivered, // Incoming is delivered by definition
        };

        if (toId.isNotEmpty) {
          if (toId == deviceId) {
            // This private message is FOR US
            _privateMessages.putIfAbsent(senderId, () => []);
            _privateMessages[senderId]!.insert(0, processedMsg);
            if (activeChatPeerId != senderId) {
              _unreadCounts[senderId] = (_unreadCounts[senderId] ?? 0) + 1;
            }
            
            // Send automatic ACK back to sender
            _sendAck(senderId, msgId);

            // Trigger notification if not in this chat
            if (activeChatPeerId != senderId) {
              _notificationController.add({
                'peerId': senderId,
                'senderName': processedMsg['senderName'],
                'text': processedMsg['message'],
              });
            }
            notifyListeners();
          }
        } else {
          // Public message
          _publicMessages.insert(0, processedMsg);
          
          // Trigger notification if not in public feed
          if (activeChatPeerId != 'public') {
            _notificationController.add({
              'peerId': 'public',
              'senderName': processedMsg['senderName'],
              'text': processedMsg['message'],
            });
          }
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Error parsing message: $e');
      }
    });
  }

  void _handleAck(String senderId, String originalMsgId) {
    if (!_privateMessages.containsKey(senderId)) return;
    
    final messages = _privateMessages[senderId]!;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['id'] == originalMsgId) {
        messages[i] = {
          ...messages[i],
          'status': MessageStatus.delivered,
        };
        debugPrint('Message $originalMsgId ACKed by $senderId');
        notifyListeners();
        break;
      }
    }
  }

  Future<void> _sendAck(String targetId, String msgId) async {
    final payload = jsonEncode({
      'id':        _generateMsgId(),
      'type':      'ACK',
      'senderId':  deviceId,
      'payload':   msgId, // ACKing the original message id
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    
    // Attempt ACK via all channels
    _channelService.sendMessage(targetId, payload).catchError((_) => false);
    _channelService.sendBleMessage(payload).catchError((_) => false);
  }

  // ─── Mesh control ─────────────────────────────────────────────────────────

  Future<void> startMesh() async {
    try {
      await _channelService.startLanDiscovery();
    } catch (e) {
      debugPrint('LAN error: $e');
    }
    try {
      await _channelService.startDiscovery();
    } catch (e) {
      debugPrint('Wi-Fi Direct error: $e');
    }
    try {
      await _channelService.startBle();
    } catch (e) {
      debugPrint('BLE error: $e');
    }
  }

  /// Clears the peer list and restarts all radios. Use when discovery feels 'stuck'.
  Future<void> refreshMesh() async {
    debugPrint('MeshProvider: Refreshing all mesh protocols...');
    _activePeers.clear();
    peerNames.clear();
    notifyListeners();
    
    await stopMesh();
    await Future.delayed(const Duration(milliseconds: 500));
    await startMesh();
  }

  Future<void> stopMesh() async {
    await _channelService.stopDiscovery().catchError((_) => false);
    await _channelService.stopBle().catchError((_) => false);
  }

  // ─── Messaging ────────────────────────────────────────────────────────────

  /// Generate a unique message ID to prevent duplicates.
  String _generateMsgId() {
    final rand = Random().nextInt(999999).toRadixString(36);
    return '${DateTime.now().millisecondsSinceEpoch}_$rand';
  }

  Future<void> broadcastPublicMessage(String text) async {
    final msgId = _generateMsgId();
    _seenMessageIds.add(msgId);

    final payload = jsonEncode({
      'id':             msgId,
      'type':           'TEXT',
      'senderId':       deviceId,
      'senderCallsign': callsign,
      'payload':        text,
      'timestamp':      DateTime.now().millisecondsSinceEpoch,
    });

    _publicMessages.insert(0, {
      'id':         msgId,
      'message':    text,
      'sender':     'me',
      'senderName': 'Me',
      'time':       _nowLabel(),
      'epochMs':    DateTime.now().millisecondsSinceEpoch,
      'status':     MessageStatus.sent,
    });
    notifyListeners();

    try {
      await _channelService.broadcastMessage(payload);
      await _channelService.sendBleMessage(payload);
    } catch (e) {
      debugPrint('Broadcast error: $e');
    }
  }

  Future<void> sendPrivateMessage(String toId, String text) async {
    final msgId = _generateMsgId();
    _seenMessageIds.add(msgId);

    final payload = jsonEncode({
      'id':             msgId,
      'type':           'TEXT',
      'to':             toId,
      'payload':        text,
      'senderId':       deviceId,
      'senderCallsign': callsign,
      'timestamp':      DateTime.now().millisecondsSinceEpoch,
    });

    final epochMs = DateTime.now().millisecondsSinceEpoch;

    // Show optimistically in UI with 'sending' status
    _privateMessages.putIfAbsent(toId, () => []);
    _privateMessages[toId]!.insert(0, {
      'id':         msgId,
      'message':    text,
      'sender':     'me',
      'senderName': 'Me',
      'time':       _nowLabel(),
      'epochMs':    epochMs,
      'status':     MessageStatus.sending,
    });
    notifyListeners();

    try {
      // Strategy 1: Targeted UDP
      final directOk = await _channelService.sendMessage(toId, payload).catchError((_) => false);
      
      // Strategy 2: BLE GATT
      final bleOk = await _channelService.sendBleMessage(payload).catchError((_) => false);

      // Update local status to 'sent' (local transmission successful)
      _updateMessageStatus(toId, msgId, (directOk || bleOk) ? MessageStatus.sent : MessageStatus.failed);
      
      debugPrint('Private → $toId: directOk=$directOk, bleOk=$bleOk');
    } catch (e) {
      debugPrint('Send error: $e');
      _updateMessageStatus(toId, msgId, MessageStatus.failed);
    }
  }

  void _updateMessageStatus(String peerId, String msgId, MessageStatus status) {
    if (!_privateMessages.containsKey(peerId)) return;
    
    final messages = _privateMessages[peerId]!;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['id'] == msgId) {
        // Don't downgrade from 'delivered'
        if (messages[i]['status'] == MessageStatus.delivered) return;
        
        messages[i] = {
          ...messages[i],
          'status': status,
        };
        debugPrint('Message $msgId status updated to $status');
        notifyListeners();
        break;
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  String _nowLabel() {
    final t = DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _autoDeleteTimer?.cancel();
    _peersSub?.cancel();
    _messagesSub?.cancel();
    _notificationController.close();
    _channelService.dispose();
    super.dispose();
  }
}
