import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MeshChannelService {
  static const MethodChannel _methodChannel = MethodChannel('com.aegis.mesh/nav');
  static const EventChannel _eventChannel = EventChannel('com.aegis.mesh/events');

  final StreamController<List<Map<String, dynamic>>> _peersController = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _messagesController = StreamController.broadcast();

  Stream<List<Map<String, dynamic>>> get peersStream => _peersController.stream;
  Stream<Map<String, dynamic>> get messagesStream => _messagesController.stream;

  MeshChannelService() {
    _eventChannel.receiveBroadcastStream().listen(_onEvent, onError: _onError);
  }

  void _onEvent(dynamic event) {
    try {
      debugPrint('EventChannel NATIVE RECEIVED: $event');
      if (event is Map) {
        final type = event['type'];
        if (type == 'peersFound') {
          final List<dynamic> peersList = event['peers'] ?? [];
          final typedPeers = peersList.map((p) {
            if (p is Map) {
              return p.map((key, value) => MapEntry(key.toString(), value));
            }
            return <String, dynamic>{};
          }).toList();

          _peersController.add(typedPeers);
          debugPrint('Dart _peersController: ${typedPeers.length} peers');
        } else if (type == 'messageReceived') {
          _messagesController.add({
            'message': event['message'],
            'sender': event['sender'],
            'transport': event['transport'] ?? 'udp',
          });
          debugPrint('Dart: inbound message from ${event["sender"]} via ${event["transport"] ?? "udp"}');
        } else if (type == 'discoveryState') {
          debugPrint('Discovery state: ${event["state"]}');
        } else if (type == 'error') {
          debugPrint('Native error: ${event["message"]}');
        }
      }
    } catch (e, stacktrace) {
      debugPrint('CRITICAL FAIL: EventChannel parse error: $e\n$stacktrace');
    }
  }

  void _onError(Object error) {
    debugPrint('EventChannel error: $error');
  }

  /// Returns the native ANDROID_ID used in beacons and peer routing.
  /// This MUST be used as the MeshProvider's deviceId so that
  /// private message filtering (toId == deviceId) works correctly.
  Future<String> getDeviceId() async {
    try {
      final result = await _methodChannel.invokeMethod<String>('getDeviceId');
      return result ?? '';
    } on PlatformException catch (e) {
      debugPrint('PlatformException [getDeviceId]: ${e.message}');
      return '';
    }
  }

  Future<bool> startDiscovery() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startDiscovery');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [startDiscovery]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> startLanDiscovery() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startLanDiscovery');
      debugPrint('LAN Beacon Discovery started');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [startLanDiscovery]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> stopDiscovery() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopDiscovery');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [stopDiscovery]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  /// Pushes the user's callsign to the native layer so it's embedded in beacons.
  Future<bool> setCallsign(String callsign) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('setCallsign', {'callsign': callsign});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [setCallsign]: ${e.message}');
      return false;
    }
  }

  Future<bool> broadcastMessage(String message) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('broadcastMessage', {'message': message});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [broadcastMessage]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> sendMessage(String targetId, String message) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('sendMessage', {'targetId': targetId, 'message': message});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [sendMessage]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> startBle() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startBle');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [startBle]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> stopBle() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopBle');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [stopBle]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  Future<bool> sendBleMessage(String message) async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('sendBleMessage', {'message': message});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('PlatformException [sendBleMessage]: ${e.message}');
      throw Exception(e.message ?? 'Unknown Platform Error');
    }
  }

  void dispose() {
    _peersController.close();
    _messagesController.close();
  }
}
