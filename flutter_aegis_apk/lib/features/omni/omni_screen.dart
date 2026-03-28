import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/mesh_provider.dart';

class OmniScreen extends ConsumerStatefulWidget {
  const OmniScreen({super.key});

  @override
  ConsumerState<OmniScreen> createState() => _OmniScreenState();
}

class _OmniScreenState extends ConsumerState<OmniScreen> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    ref.read(meshProvider).broadcastPublicMessage(text);
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(meshProvider).publicMessages;
    
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Omni Protocol', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2)),
            Text('PUBLIC SQUARE (TACTICAL FEED)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, size: 18),
            onPressed: () {
              ref.read(meshProvider).refreshMesh();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Protocol Resync: Clearing peers and re-scanning...'),
                  backgroundColor: Color(0xFF00D1FF),
                  behavior: SnackBarBehavior.floating,
                )
              );
            },
            tooltip: 'Initiate Protocol',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 8),
            child: Row(
              children: const [
                Icon(Icons.code, size: 16),
                SizedBox(width: 8),
                Text('LIVE BROADCASTS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: feed.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Listening for broadcasts...', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: feed.length,
                    itemBuilder: (context, index) {
                      final msg = feed[index];
                      // Use true identity if sender is marked 'me' or matches our ID
                      final isMe = msg['sender'] == 'me' || msg['sender'] == ref.read(meshProvider).deviceId;
                      final time = msg['time'] as String? ?? '--:--';
                      final senderName = msg['senderName'] as String? ?? msg['sender'] as String? ?? 'Ghost';

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                                : Theme.of(context).primaryColor.withValues(alpha: 0.05),
                            border: Border.all(
                                color: isMe
                                    ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                                    : Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(isMe ? 12 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Text(senderName,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context).primaryColor,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1)),
                              if (!isMe) const SizedBox(height: 4),
                              Text(msg['message'] as String? ?? '', style: const TextStyle(fontSize: 14)),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(time, style: const TextStyle(fontSize: 8, color: Colors.white30)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.2))),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Transmit to Public Square...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Theme.of(context).primaryColor),
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
