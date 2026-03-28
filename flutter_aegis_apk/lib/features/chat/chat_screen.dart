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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Mark as active chat so incoming messages don't increment unread
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(meshProvider).activeChatPeerId = widget.peerId;
      ref.read(meshProvider).markAsRead(widget.peerId);
    });
  }

  @override
  void dispose() {
    // Clear active chat tracking when leaving screen
    ref.read(meshProvider).activeChatPeerId = null;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(meshProvider).sendPrivateMessage(widget.peerId, text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final mesh = ref.watch(meshProvider);
    final messages = mesh.getPrivateMessages(widget.peerId);
    final displayName = mesh.getDisplayName(widget.peerId);
    final primary = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary.withValues(alpha: 0.15),
                border: Border.all(color: primary.withValues(alpha: 0.4)),
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primary,
                          boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.6), blurRadius: 4)],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'E2EE ACTIVE  •  ${widget.peerId.length > 16 ? widget.peerId.substring(0, 16) + "…" : widget.peerId}',
                        style: TextStyle(fontSize: 9, color: primary.withValues(alpha: 0.7), letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.security, size: 18, color: primary.withValues(alpha: 0.7)),
            tooltip: 'Encrypted tunnel',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF0A0F14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: primary.withValues(alpha: 0.3)),
                  ),
                  title: Row(
                    children: [
                      Icon(Icons.lock, color: primary, size: 18),
                      const SizedBox(width: 8),
                      Text('Tunnel Info', style: TextStyle(color: primary, fontSize: 14)),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('Protocol', 'Double Ratchet + X3DH'),
                      _infoRow('Cipher', 'AES-256-GCM'),
                      _infoRow('Transport', 'BLE + LAN UDP'),
                      _infoRow('Peer ID', widget.peerId),
                      _infoRow('Status', 'No server. Fully offline.'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('CLOSE', style: TextStyle(color: primary)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Encrypted tunnel banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: primary.withValues(alpha: 0.06),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 10, color: primary.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Text(
                    'Messages are end-to-end encrypted. No server. No log.',
                    style: TextStyle(fontSize: 9, color: primary.withValues(alpha: 0.6), letterSpacing: 0.5),
                  ),
                ],
              ),
            ),
          ),

          // Message list
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: primary.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        Text('No messages yet', style: TextStyle(color: Colors.white30, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('Say hi to $displayName', style: TextStyle(color: Colors.white24, fontSize: 10)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender'] == 'me';
                      final text = msg['message'] as String? ?? '';
                      final time = msg['time'] as String? ?? '';
                      final status = msg['status'] as MessageStatus? ?? MessageStatus.delivered;

                      // Show date separator for first message or day changes (simplified)
                      return _MessageBubble(
                        text: text,
                        time: time,
                        isMe: isMe,
                        status: status,
                        senderName: isMe ? null : (msg['senderName'] as String?),
                      );
                    },
                  ),
          ),

          // Input bar
          _buildInputBar(primary),
        ],
      ),
    );
  }

  Widget _buildInputBar(Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: primary.withOpacity(0.15))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  border: Border.all(color: primary.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(fontSize: 15),
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: 'Encrypted message...',
                          hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.mic_none_rounded, color: Colors.white38, size: 20),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendMessage,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primary,
                  boxShadow: [BoxShadow(color: primary.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)],
                ),
                child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white30, letterSpacing: 1)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isMe;
  final MessageStatus status;
  final String? senderName;

  const _MessageBubble({
    required this.text,
    required this.time,
    required this.isMe,
    required this.status,
    this.senderName,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: isMe
                    ? primary.withOpacity(0.18)
                    : Colors.white.withOpacity(0.07),
                border: Border.all(
                  color: isMe
                      ? primary.withOpacity(0.45)
                      : Colors.white.withOpacity(0.1),
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 2),
                  bottomRight: Radius.circular(isMe ? 2 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sender name for inbound messages
                  if (!isMe && senderName != null && senderName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        senderName!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMe ? Colors.white : Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        time,
                        style: const TextStyle(fontSize: 9, color: Colors.white30),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 6),
                        _buildStatusIcon(primary),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Color primary) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 8,
          height: 8,
          child: CircularProgressIndicator(strokeWidth: 1.2, color: primary.withOpacity(0.5)),
        );
      case MessageStatus.sent:
        return const Icon(Icons.done, size: 12, color: Colors.white24);
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 12, color: primary);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
    }
  }
}
