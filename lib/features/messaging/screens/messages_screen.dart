import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intellibreak/features/auth/services/api_service.dart';
import 'package:intellibreak/features/messaging/services/messaging_service.dart';
import 'package:intellibreak/features/messaging/providers/messaging_provider.dart';
import 'package:intellibreak/features/messaging/screens/chat_screen.dart';
import 'package:intellibreak/features/messaging/widgets/participant_avatar.dart';
import 'package:intellibreak/features/messaging/widgets/unread_badge.dart';

class MessagesScreenContent extends StatefulWidget {
  const MessagesScreenContent({super.key});

  @override
  State<MessagesScreenContent> createState() => _MessagesScreenContentState();
}

class _MessagesScreenContentState extends State<MessagesScreenContent> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedConversationId;
  String? _selectedParticipantName;
  String? _selectedParticipantRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<MessagingProvider>();
      provider.loadConversations();
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showNewMessageDialog(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final currentUserId = context.read<MessagingProvider>().currentUserId;
    showDialog(
      context: context,
      builder: (context) => _NewMessageDialog(
        isDesktop: isDesktop,
        currentUserId: currentUserId,
        onConversationSelected: (convoId, name, role) {
          setState(() {
            _selectedConversationId = convoId;
            _selectedParticipantName = name;
            _selectedParticipantRole = role;
          });
          context.read<MessagingProvider>().loadConversations();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MessagingProvider>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 900;
    final currentUserId = provider.currentUserId;

    final allConversations = provider.conversations;
    final filteredConversations = allConversations.where((c) {
      if (_searchQuery.isEmpty) return true;
      final parts = c['participants'] as List? ?? [];
      for (var p in parts) {
        if (p is Map) {
          final pid = p['id']?.toString() ?? p['user_id']?.toString();
          if (pid == currentUserId) continue;
          final name = (p['full_name'] ?? '').toLowerCase();
          final email = (p['email'] ?? '').toLowerCase();
          if (name.contains(_searchQuery) || email.contains(_searchQuery)) return true;
        }
      }
      final lastMsg = c['last_message'] as Map<String, dynamic>?;
      final content = (lastMsg?['content'] ?? '').toLowerCase();
      return content.contains(_searchQuery);
    }).toList();

    Widget buildConversationList() {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Messages',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'New Message',
                  onPressed: () => _showNewMessageDialog(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => provider.loadConversations(),
              child: provider.isLoading && allConversations.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : provider.error != null && allConversations.isEmpty
                      ? _EmptyState(
                          message: provider.error!,
                          onRetry: () => provider.loadConversations(),
                        )
                      : filteredConversations.isEmpty
                          ? _EmptyState(
                              message: 'No conversations found.',
                              onRetry: () => _showNewMessageDialog(context),
                              isAction: true,
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: filteredConversations.length,
                              itemBuilder: (context, index) {
                                final c = filteredConversations[index];
                                final convoId = c['id']?.toString() ?? '';
                                final isSelected = isDesktop && _selectedConversationId == convoId;
                                return _ConversationTile(
                                  conversation: c,
                                  isSelected: isSelected,
                                  currentUserId: currentUserId,
                                  onTap: () {
                                    if (isDesktop) {
                                      setState(() {
                                        _selectedConversationId = convoId;
                                        _extractParticipantInfo(c, currentUserId);
                                      });
                                    } else {
                                      final messagingProvider = context.read<MessagingProvider>();
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ChatScreen(conversationId: convoId),
                                        ),
                                      ).then((_) {
                                        if (mounted) {
                                          messagingProvider.loadConversations();
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                            ),
            ),
          ),
        ],
      );
    }

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 360,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: theme.dividerColor, width: 1)),
                  color: isDark ? const Color(0xFF14161B) : Colors.grey.shade100,
                ),
                child: buildConversationList(),
              ),
            ),
            Expanded(
              child: _selectedConversationId == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'Select a conversation to start chatting',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ChatScreen(
                      key: ValueKey(_selectedConversationId),
                      conversationId: _selectedConversationId!,
                      isEmbedded: true,
                      participantNameOverride: _selectedParticipantName,
                      participantRoleOverride: _selectedParticipantRole,
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14161B) : Colors.grey.shade100,
        ),
        child: buildConversationList(),
      ),
    );
  }

  void _extractParticipantInfo(Map<String, dynamic> c, String? currentUserId) {
    final parts = c['participants'] as List? ?? [];
    Map<String, dynamic>? other;
    if (currentUserId == null && parts.isNotEmpty) {
      other = parts.first as Map<String, dynamic>?;
    } else {
      for (var p in parts) {
        if (p is Map) {
          final pid = p['id']?.toString() ?? p['user_id']?.toString();
          if (pid != currentUserId) {
            other = p as Map<String, dynamic>;
            break;
          }
        }
      }
      other ??= (parts.isNotEmpty ? parts.first as Map<String, dynamic>? : null);
    }
    _selectedParticipantName = other?['full_name'] ?? other?['email'] ?? 'Colleague';
    _selectedParticipantRole = other?['role'] ?? 'EMPLOYEE';
  }
}

class _NewMessageDialog extends StatefulWidget {
  final bool isDesktop;
  final String? currentUserId;
  final Function(String convoId, String name, String role)? onConversationSelected;

  const _NewMessageDialog({
    this.isDesktop = false,
    this.currentUserId,
    this.onConversationSelected,
  });

  @override
  State<_NewMessageDialog> createState() => _NewMessageDialogState();
}

class _NewMessageDialogState extends State<_NewMessageDialog> {
  bool _isLoading = true;
  String? _error;
  List<dynamic> _members = [];
  List<dynamic> _filteredMembers = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _searchController.addListener(_filterMembers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    try {
      final token = await ApiService().getToken();
      if (token == null) {
        setState(() {
          _error = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }
      final members = await MessagingService.getOrganizationMembers(token);
      if (mounted) {
        setState(() {
          _members = members;
          _filteredMembers = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _filterMembers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMembers = _members.where((m) {
        final name = (m['full_name'] ?? '').toLowerCase();
        final email = (m['email'] ?? '').toLowerCase();
        return name.contains(query) || email.contains(query);
      }).toList();
    });
  }

  Future<void> _startChat(String userId, String name, String role) async {
    try {
      final token = await ApiService().getToken();
      if (token == null) return;
      final result = await MessagingService.createDirect(token, userId);
      final convoId = result['id']?.toString();
      if (!mounted) return;
      if (convoId != null) {
        Navigator.of(context).pop();
        if (!mounted) return;
        if (widget.isDesktop && widget.onConversationSelected != null) {
          widget.onConversationSelected!(convoId, name, role);
        } else {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: convoId,
                participantNameOverride: name,
                participantRoleOverride: role,
              ),
            ),
          ).then((_) {
            if (mounted) {
              context.read<MessagingProvider>().loadConversations();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Conversation'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search colleagues...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                      : _filteredMembers.isEmpty
                          ? const Center(child: Text('No colleagues found'))
                          : ListView.builder(
                              itemCount: _filteredMembers.length,
                              itemBuilder: (context, index) {
                                final member = _filteredMembers[index];
                                final name = member['full_name'] ?? 'Colleague';
                                final email = member['email'] ?? '';
                                final role = member['role'] ?? 'EMPLOYEE';
                                final formattedRole = role[0].toUpperCase() + role.substring(1).toLowerCase();

                                return ListTile(
                                  leading: ParticipantAvatar(name: name, role: role, size: 40),
                                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text('$email • $formattedRole'),
                                  onTap: () => _startChat(member['id'].toString(), name, role),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final dynamic conversation;
  final bool isSelected;
  final VoidCallback onTap;
  final String? currentUserId;

  const _ConversationTile({
    required this.conversation,
    required this.isSelected,
    required this.onTap,
    this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final other = _getOtherParticipant();
    final name = other?['full_name'] ?? other?['email'] ?? 'Participant';
    final role = other?['role']?.toString() ?? 'EMPLOYEE';
    final preview = _lastPreview();
    final time = _lastTimestamp();
    final unread = (conversation['unread_count'] ?? 0) as int;

    return Container(
      color: isSelected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
      child: ListTile(
        leading: ParticipantAvatar(name: name, role: role, size: 44),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: unread > 0 ? FontWeight.bold : FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (time.isNotEmpty)
              Text(
                time,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  preview,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: unread > 0
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unread > 0) ...[
                const SizedBox(width: 8),
                UnreadBadge(count: unread),
              ],
            ],
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  Map<String, dynamic>? _getOtherParticipant() {
    final parts = conversation['participants'] as List? ?? [];
    if (parts.isEmpty) return null;
    if (currentUserId == null) return parts.first as Map<String, dynamic>?;
    for (var p in parts) {
      if (p is Map) {
        final pid = p['id']?.toString() ?? p['user_id']?.toString();
        if (pid != currentUserId) {
          return p as Map<String, dynamic>;
        }
      }
    }
    return parts.first as Map<String, dynamic>?;
  }

  String _lastPreview() {
    final msg = conversation['last_message'] as Map<String, dynamic>?;
    if (msg == null || msg['content'] == null) return 'No messages yet';
    return msg['content'].toString();
  }

  String _lastTimestamp() {
    final msg = conversation['last_message'] as Map<String, dynamic>?;
    if (msg == null || msg['created_at'] == null) return '';
    try {
      final dt = DateTime.parse(msg['created_at'].toString()).toLocal();
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool isAction;

  const _EmptyState({
    required this.message,
    required this.onRetry,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: Icon(isAction ? Icons.edit : Icons.refresh),
              label: Text(isAction ? 'Start Conversation' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
