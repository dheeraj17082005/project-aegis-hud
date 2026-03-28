import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/mesh_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String peerId;

  const ChatScreen({super.key, required this.peerId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    ref.read(meshProvider).sendPrivateMessage(widget.peerId, _controller.text);
    _controller.clear();
  }

  List<Message> _getAllMessages() {
    // Both sent AND received private messages are now stored in `privateMessages` by the provider
    final inbound = ref.watch(meshProvider).getPrivateMessages(widget.peerId);
    return inbound.map((msg) => Message(
      sender: msg['sender'] as String? ?? 'Ghost',
      text: msg['message'] as String? ?? '',
      time: msg['time'] as String? ?? '${DateTime.now().hour.toString().padLeft(2,'0')}:${DateTime.now().minute.toString().padLeft(2,'0')}',
      isMe: (msg['sender'] == 'me'),
    )).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allMessages = _getAllMessages();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aegis Tunnel', style: TextStyle(fontSize: 10, color: Colors.white54, letterSpacing: 2)),
            Text('PEER: ${widget.peerId}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Row(
                children: [
                  Icon(Icons.security, size: 12, color: Theme.of(context).primaryColor.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Text('E2EE ACTIVE', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor.withValues(alpha: 0.6))),
                ],
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text('Vault Secured: Local Data Only. Volatile Memory Active.', style: TextStyle(fontSize: 8, color: Colors.white54, letterSpacing: 2)),
            ),
          ),
          Expanded(
            child: allMessages.isEmpty
                ? const Center(child: Text('Searching for Ghosts...', style: TextStyle(color: Colors.white54, letterSpacing: 2)))
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allMessages.length,
              itemBuilder: (context, index) {
                final msg = allMessages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: msg.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: msg.isMe ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: msg.isMe ? Theme.of(context).primaryColor.withValues(alpha: 0.4) : Colors.white24),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(8),
                  topRight: const Radius.circular(8),
                  bottomLeft: msg.isMe ? const Radius.circular(8) : Radius.zero,
                  bottomRight: msg.isMe ? Radius.zero : const Radius.circular(8),
                ),
              ),
              child: Text(msg.text, style: TextStyle(color: msg.isMe ? Colors.white : Theme.of(context).primaryColor.withValues(alpha: 0.9), fontSize: 14)),
            ),
            const SizedBox(height: 4),
            Text(msg.time, style: const TextStyle(fontSize: 8, color: Colors.white30)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Theme.of(context).primaryColor.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                border: Border.all(color: Colors.white10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.mic, color: Colors.white54), onPressed: () {}),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Secure message...',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
                    onPressed: _sendMessage,
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

class Message {
  final String sender;
  final String text;
  final String time;
  final bool isMe;

  Message({required this.sender, required this.text, required this.time, required this.isMe});
}
