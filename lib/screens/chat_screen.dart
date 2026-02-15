import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../widgets/profile_avatar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.connectionInfo,
  });

  final User currentUser;
  final ConnectionInfo connectionInfo;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Message> _messages = [];
  DocumentSnapshot? _oldestDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSending = false;
  StreamSubscription<List<Message>>? _messagesSubscription;

  static const int _pageSize = 10;
  static const Color _myBubbleColor = Color(0xFF1D731D);
  static const Color _otherBubbleColor = Color(0xFF2929A2);
  static const Color _bubbleTextColor = Color(0xFFF0F8FF);

  @override
  void initState() {
    super.initState();
    _updateLastSeen();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _updateLastSeen() async {
    await _firestoreService.updateParticipantLastSeen(
      connectionId: widget.connectionInfo.connectionId,
      userId: widget.currentUser.userId,
    );
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _listenForNewMessages() {
    _messagesSubscription?.cancel();
    final newestAt = _messages.isNotEmpty
        ? _messages.last.createdAt
        : DateTime(1970);
    _messagesSubscription = _firestoreService
        .messagesStream(
          connectionId: widget.connectionInfo.connectionId,
          after: newestAt,
        )
        .listen((newMessages) async {
      if (newMessages.isEmpty || !mounted) return;
      setState(() {
        final existingIds = _messages.map((m) => m.id).toSet();
        for (final m in newMessages) {
          if (!existingIds.contains(m.id)) {
            _messages.add(m);
            existingIds.add(m.id);
          }
        }
      });
      await _firestoreService.updateParticipantLastSeen(
        connectionId: widget.connectionInfo.connectionId,
        userId: widget.currentUser.userId,
      );
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadInitialMessages() async {
    final result = await _firestoreService.getMessagesPage(
      connectionId: widget.connectionInfo.connectionId,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.addAll(result.messages.reversed);
      _oldestDoc = result.oldestDoc;
      _hasMore = result.messages.length >= _pageSize;
    });
    _listenForNewMessages();
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _oldestDoc == null) return;
    setState(() => _isLoadingMore = true);

    final result = await _firestoreService.getMessagesPage(
      connectionId: widget.connectionInfo.connectionId,
      limit: _pageSize,
      startAfterDoc: _oldestDoc,
    );

    if (!mounted) return;
    setState(() {
      _isLoadingMore = false;
      if (result.messages.isEmpty) {
        _hasMore = false;
      } else {
        _messages.insertAll(0, result.messages.reversed);
        _oldestDoc = result.oldestDoc;
        _hasMore = result.messages.length >= _pageSize;
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    _textController.clear();
    setState(() => _isSending = true);

    try {
      await _firestoreService.sendMessage(
        connectionId: widget.connectionInfo.connectionId,
        senderId: widget.currentUser.userId,
        text: text,
      );
      if (mounted) {
        setState(() => _isSending = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: widget.connectionInfo.isGroup
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundImage: AssetImage('assets/default.png'),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      widget.connectionInfo.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              )
            : StreamBuilder<Map<String, dynamic>?>(
                stream: _firestoreService.userProfileStream(
                  widget.connectionInfo.otherUserId,
                ),
                builder: (context, snapshot) {
                  final otherUser = snapshot.hasData && snapshot.data != null
                      ? User.fromFirestore(
                          snapshot.data!,
                          widget.connectionInfo.otherUserId,
                        )
                      : User(
                          userId: widget.connectionInfo.otherUserId,
                          email: '',
                          username: widget.connectionInfo.name,
                        );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ProfileAvatar(
                        user: otherUser,
                        radius: 18,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          otherUser.username,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                },
              ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.connectionInfo.isGroup
              ? _buildMessagesList(
                  otherLastSeen: null,
                  otherUser: User(
                    userId: '',
                    email: '',
                    username: widget.connectionInfo.name,
                  ),
                )
              : StreamBuilder<Map<String, dynamic>?>(
                  stream: _firestoreService.participantStream(
                    connectionId: widget.connectionInfo.connectionId,
                    userId: widget.connectionInfo.otherUserId,
                  ),
                  builder: (context, participantSnapshot) {
                    final participantData = participantSnapshot.data;
                    final lastSeenTs = participantData?['lastSeen'];
                    final DateTime? otherLastSeen = lastSeenTs is Timestamp
                        ? lastSeenTs.toDate()
                        : null;

                    return StreamBuilder<Map<String, dynamic>?>(
                      stream: _firestoreService.userProfileStream(
                        widget.connectionInfo.otherUserId,
                      ),
                      builder: (context, userSnapshot) {
                        final otherUser = userSnapshot.hasData &&
                                userSnapshot.data != null
                            ? User.fromFirestore(
                                userSnapshot.data!,
                                widget.connectionInfo.otherUserId,
                              )
                            : User(
                                userId: widget.connectionInfo.otherUserId,
                                email: '',
                                username: widget.connectionInfo.name,
                              );

                        return _buildMessagesList(
                          otherLastSeen: otherLastSeen,
                          otherUser: otherUser,
                        );
                      },
                    );
                  },
                ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Future<void> _showMessageOptions(BuildContext context, Message msg) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Modify'),
              onTap: () => Navigator.pop(context, 'modify'),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context, 'cancel'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || result == null || result == 'cancel') return;

    if (result == 'modify') {
      await _modifyMessage(msg);
    } else if (result == 'delete') {
      await _deleteMessage(msg);
    }
  }

  Future<void> _modifyMessage(Message msg) async {
    final controller = TextEditingController(text: msg.text);

    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Message',
          ),
          maxLines: null,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newText == null || !mounted || newText == msg.text) return;

    try {
      await _firestoreService.updateMessage(
        connectionId: widget.connectionInfo.connectionId,
        messageId: msg.id,
        newText: newText,
      );
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == msg.id);
          if (i >= 0) {
            _messages[i] = Message(
              id: msg.id,
              senderId: msg.senderId,
              text: newText,
              createdAt: msg.createdAt,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(Message msg) async {
    try {
      await _firestoreService.deleteMessage(
        connectionId: widget.connectionInfo.connectionId,
        messageId: msg.id,
      );
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m.id == msg.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Finds the most recent message (sent by me) that the other user has seen.
  Message? _findLastSeenMessage(DateTime? otherLastSeen) {
    if (otherLastSeen == null) return null;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final msg = _messages[i];
      if (msg.senderId == widget.currentUser.userId &&
          !otherLastSeen.isBefore(msg.createdAt)) {
        return msg;
      }
    }
    return null;
  }

  Widget _buildMessagesList({
    required DateTime? otherLastSeen,
    required User otherUser,
  }) {
    if (_messages.isEmpty && !_isLoadingMore) {
      return const Center(
        child: Text(
          'No messages yet',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    final lastSeenMessage = _findLastSeenMessage(otherLastSeen);

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length + (_hasMore && _isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final msg = _messages[_messages.length - 1 - index];
        final isMe = msg.senderId == widget.currentUser.userId;
        final showSeenBy = isMe && msg.id == lastSeenMessage?.id;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: isMe
                      ? () => _showMessageOptions(context, msg)
                      : null,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? _myBubbleColor : _otherBubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                    ),
                    child: Text(
                      msg.text,
                      style: const TextStyle(
                        color: _bubbleTextColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              if (showSeenBy) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ProfileAvatar(user: otherUser, radius: 12),
                    const SizedBox(width: 6),
                    Text(
                      'Seen by ${otherUser.username}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isSending ? null : _sendMessage,
            icon: _isSending
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
