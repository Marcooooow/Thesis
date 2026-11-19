import 'package:flutter/material.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/messaging/services/messaging_service.dart';
import 'package:intellibreak/features/messaging/widgets/chat_header.dart';
import 'package:intellibreak/features/messaging/widgets/date_separator.dart';
import 'package:intellibreak/features/messaging/widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final bool isEmbedded;
  final String? participantNameOverride;
  final String? participantRoleOverride;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.isEmbedded = false,
    this.participantNameOverride,
    this.participantRoleOverride,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _loadingHistory = false;
  List<dynamic> _messages = [];
  int _offset = 0;
  int _total = 0;
  bool _polling = false;
  bool _disposed = false;
  String? _currentUserId;
  String _participantName = 'Chat';
  String _participantRole = 'Employee';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startPolling() {
    Future.delayed(const Duration(seconds: 7), () {
      if (!_disposed && mounted) {
        _pollUpdates();
        _startPolling();
      }
    });
  }

  Future<void> _pollUpdates() async {
    if (_polling || _disposed || !mounted) return;
    _polling = true;
    try {
      final token = await ApiService().getToken();
      if (token == null) return;
      final data = await MessagingService.getMessages(token, widget.conversationId, limit: 50, offset: 0);
      if (!_disposed && mounted) {
        setState(() {
          _messages = data['messages'] ?? [];
          _total = data['total'] ?? 0;
        });
      }
    } catch (_) {}
    finally {
      _polling = false;
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final token = await ApiService().getToken();
      if (token == null) {
        if (mounted) setState(() => _loadingHistory = false);
        return;
      }
      try {
        final me = await ApiService().getMe(token);
        _currentUserId = me['id']?.toString();
      } catch (_) {}

      if (widget.participantNameOverride == null) {
        try {
          final convsData = await MessagingService.getConversations(token);
          final convs = convsData['conversations'] as List? ?? [];
          for (var c in convs) {
            if (c['id']?.toString() == widget.conversationId) {
              final parts = c['participants'] as List? ?? [];
              for (var p in parts) {
                if (p is Map && p['id']?.toString() != _currentUserId) {
                  _participantName = p['full_name'] ?? p['email'] ?? 'Colleague';
                  _participantRole = p['role'] ?? 'EMPLOYEE';
                  break;
                }
              }
              break;
            }
          }
        } catch (_) {}
      } else {
        _participantName = widget.participantNameOverride!;
        _participantRole = widget.participantRoleOverride ?? 'EMPLOYEE';
      }

      final data = await MessagingService.getMessages(token, widget.conversationId, limit: 50, offset: 0);
      if (mounted) {
        setState(() {
          _messages = data['messages'] ?? [];
          _total = data['total'] ?? 0;
          _offset = 0;
          _loadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final token = await ApiService().getToken();
      if (token == null) throw Exception('Not authenticated');
      await MessagingService.sendMessage(token, widget.conversationId, text);
      _controller.clear();
      await _loadHistory();
      if (!mounted) return;
      await MessagingService.markRead(token, widget.conversationId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_offset >= _total) return;
    try {
      final token = await ApiService().getToken();
      if (token == null) return;
      final next = _offset + 50;
      final data = await MessagingService.getMessages(token, widget.conversationId, limit: 50, offset: next);
      if (mounted) {
        setState(() {
          _messages = [...(data['messages'] ?? []), ..._messages];
          _offset = next;
          _total = data['total'] ?? _total;
        });
      }
    } catch (_) {}
  }

  String _formatDateLabel(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
        return 'Yesterday';
      }
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _formatTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = ChatHeader(
      participantName: _participantName,
      participantRole: _participantRole,
      onBackPressed: widget.isEmbedded ? null : () => Navigator.of(context).pop(),
      onMarkRead: () async {
        final sm = ScaffoldMessenger.of(context);
        final token = await ApiService().getToken();
        if (!mounted) return;
        if (token != null) {
          await MessagingService.markRead(token, widget.conversationId);
          if (!mounted) return;
          sm.showSnackBar(const SnackBar(content: Text('Conversation marked as read')));
        }
      },
    );

    final chatBody = Column(
      children: [
        if (widget.isEmbedded) header,
        Expanded(
          child: _loadingHistory && _messages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No messages yet. Start the conversation by sending a message below!',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      itemCount: _messages.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          if (_offset >= _total) return const SizedBox.shrink();
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TextButton.icon(
                                onPressed: _loadOlder,
                                icon: const Icon(Icons.history),
                                label: const Text('Load earlier messages'),
                              ),
                            ),
                          );
                        }

                        final msg = _messages[index - 1];
                        final senderId = msg['sender_id']?.toString();
                        final isMe = _currentUserId != null && senderId == _currentUserId;
                        final createdAt = msg['created_at']?.toString();

                        bool showDateSeparator = false;
                        String dateLabel = '';
                        if (createdAt != null) {
                          dateLabel = _formatDateLabel(createdAt);
                          if (index == 1) {
                            showDateSeparator = true;
                          } else {
                            final prevMsg = _messages[index - 2];
                            final prevDateLabel = _formatDateLabel(prevMsg['created_at']?.toString());
                            if (dateLabel != prevDateLabel) {
                              showDateSeparator = true;
                            }
                          }
                        }

                        return Column(
                          children: [
                            if (showDateSeparator && dateLabel.isNotEmpty)
                              DateSeparator(dateText: dateLabel),
                            MessageBubble(
                              content: msg['content'] ?? '',
                              timestamp: _formatTime(createdAt),
                              isMe: isMe,
                            ),
                          ],
                        );
                      },
                    ),
        ),
        const Divider(height: 1),
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLines: 4,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    enabled: !_sending,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (widget.isEmbedded) {
      return chatBody;
    }

    return Scaffold(
      appBar: header,
      body: chatBody,
    );
  }
}
