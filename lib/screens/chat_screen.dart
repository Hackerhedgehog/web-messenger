import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/connection_info.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../widgets/media_message_content.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/profile_popup.dart';

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
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Message> _messages = [];
  DocumentSnapshot? _oldestDoc;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSending = false;
  StreamSubscription<List<Message>>? _messagesSubscription;
  DateTime? _lastTypingUpdateAt;

  static const int _pageSize = 10;
  static const int _typingThresholdSeconds = 5;
  static const Color _myBubbleColor = Color(0xFF1D731D);
  static const Color _otherBubbleColor = Color(0xFF2929A2);
  static const Color _bubbleTextColor = Color(0xFFF0F8FF);

  Timer? _typingCheckTimer;

  @override
  void initState() {
    super.initState();
    _updateLastSeen();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
    _typingCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _updateLastSeen() async {
    await _firestoreService.updateParticipantLastSeen(
      connectionId: widget.connectionInfo.connectionId,
      userId: widget.currentUser.userId,
    );
  }

  @override
  void dispose() {
    _typingCheckTimer?.cancel();
    _messagesSubscription?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _listenToMessages() {
    _messagesSubscription?.cancel();

    final floor = _messages.isNotEmpty
        ? _messages.first.createdAt
        : DateTime(1970);
    _messagesSubscription = _firestoreService
        .messagesInRangeStream(
          connectionId: widget.connectionInfo.connectionId,
          createdAtFloor: floor,
        )
        .listen((messages) async {
          if (!mounted) return;
          setState(() {
            _messages.clear();
            _messages.addAll(messages);
          });
          await _firestoreService.updateParticipantLastSeen(
            connectionId: widget.connectionInfo.connectionId,
            userId: widget.currentUser.userId,
          );
        });
  }

  void _onTyping() {
    final now = DateTime.now();
    if (_lastTypingUpdateAt != null &&
        now.difference(_lastTypingUpdateAt!).inSeconds <
            _typingThresholdSeconds) {
      return;
    }
    _lastTypingUpdateAt = now;
    _firestoreService.updateParticipantLastTyping(
      connectionId: widget.connectionInfo.connectionId,
      userId: widget.currentUser.userId,
    );
  }

  static bool _isTypingRecently(Map<String, dynamic>? data) {
    if (data == null) return false;
    final lt = data['lastTyping'];
    if (lt is! Timestamp) return false;
    return DateTime.now().difference(lt.toDate()).inSeconds <
        _typingThresholdSeconds;
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMoreMessages();
    }
  }

  void _onTitleTap(BuildContext context) {
    if (widget.connectionInfo.isGroup) {
      _showGroupParticipants(context);
    } else {
      _showOtherUserProfile(context);
    }
  }

  void _showOtherUserProfile(BuildContext context) async {
    final data = await _firestoreService.getUserProfile(
      widget.connectionInfo.otherUserId,
    );
    if (!context.mounted) return;
    final user = data != null
        ? User.fromFirestore(data, widget.connectionInfo.otherUserId)
        : User(
            userId: widget.connectionInfo.otherUserId,
            email: '',
            username: widget.connectionInfo.name,
          );
    showProfilePopup(context: context, user: user);
  }

  void _showGroupParticipants(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${widget.connectionInfo.name} - Participants',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Flexible(
              child: ListView.builder(
                controller: scrollController,
                shrinkWrap: true,
                itemCount: widget.connectionInfo.participantIds.length,
                itemBuilder: (context, index) {
                  final userId = widget.connectionInfo.participantIds[index];
                  return _ChatParticipantTile(
                    userId: userId,
                    firestoreService: _firestoreService,
                    isCurrentUser: userId == widget.currentUser.userId,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
    _listenToMessages();
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
        _listenToMessages();
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

  Future<void> _pickAndSendMedia() async {
    if (_isSending) return;

    try {
      String? filename;
      List<int>? bytes;
      XFile? xFile;

      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'mp4', 'mov', 'webm', 'mkv'],
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;
        if (file.bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not read file')),
            );
          }
          return;
        }
        filename = file.name;
        bytes = file.bytes;
      } else {
        final choice = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Photo'),
                  onTap: () => Navigator.pop(context, 'image'),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam),
                  title: const Text('Video'),
                  onTap: () => Navigator.pop(context, 'video'),
                ),
              ],
            ),
          ),
        );
        if (choice == null) return;

        if (choice == 'image') {
          final image = await _imagePicker.pickImage(source: ImageSource.gallery);
          if (image != null) {
            xFile = image;
            filename = image.name;
          }
        } else {
          final video = await _imagePicker.pickVideo(source: ImageSource.gallery);
          if (video != null) {
            xFile = video;
            filename = video.name;
          }
        }
        if (xFile == null) return;
      }

      if (filename == null || filename.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get file name')),
          );
        }
        return;
      }

      final mediaType = mediaTypeFromFilename(filename);
      if (mediaType == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unsupported format')),
          );
        }
        return;
      }

      setState(() => _isSending = true);

      final connectionId = widget.connectionInfo.connectionId;
      final messageId = _firestoreService.generateMessageId(connectionId);

      final uploadResult = kIsWeb && bytes != null
          ? await _storageService.uploadMessageMediaFromBytes(
              bytes: bytes,
              filename: filename,
              connectionId: connectionId,
              messageId: messageId,
            )
          : await _storageService.uploadMessageMedia(
              file: xFile!,
              connectionId: connectionId,
              messageId: messageId,
            );

      final caption = _textController.text.trim();
      _textController.clear();

      await _firestoreService.sendMessage(
        connectionId: connectionId,
        senderId: widget.currentUser.userId,
        text: caption,
        messageId: messageId,
        mediaUrl: uploadResult.url,
        mediaPath: uploadResult.path,
        mediaType: mediaType,
      );

      if (mounted) setState(() => _isSending = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send media: $e'),
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
        title: GestureDetector(
          onTap: () => _onTitleTap(context),
          child: widget.connectionInfo.isGroup
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
                        ProfileAvatar(user: otherUser, radius: 18),
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
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.connectionInfo.isGroup
                ? StreamBuilder<Map<String, Map<String, dynamic>>>(
                    stream: _firestoreService.participantsStream(
                      connectionId: widget.connectionInfo.connectionId,
                    ),
                    builder: (context, participantsSnapshot) {
                      final participants =
                          participantsSnapshot.data ??
                          <String, Map<String, dynamic>>{};
                      final typingIds = participants.entries
                          .where((e) => e.key != widget.currentUser.userId)
                          .where((e) => _isTypingRecently(e.value))
                          .map((e) => e.key)
                          .toList();

                      return Column(
                        children: [
                          Expanded(
                            child: _buildMessagesList(
                              otherLastSeen: null,
                              otherUser: User(
                                userId: '',
                                email: '',
                                username: widget.connectionInfo.name,
                              ),
                            ),
                          ),
                          if (typingIds.isNotEmpty)
                            _TypingIndicator(
                              firestoreService: _firestoreService,
                              typingUserIds: typingIds,
                            ),
                        ],
                      );
                    },
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
                      final otherIsTyping = _isTypingRecently(participantData);

                      return StreamBuilder<Map<String, dynamic>?>(
                        stream: _firestoreService.userProfileStream(
                          widget.connectionInfo.otherUserId,
                        ),
                        builder: (context, userSnapshot) {
                          final otherUser =
                              userSnapshot.hasData && userSnapshot.data != null
                              ? User.fromFirestore(
                                  userSnapshot.data!,
                                  widget.connectionInfo.otherUserId,
                                )
                              : User(
                                  userId: widget.connectionInfo.otherUserId,
                                  email: '',
                                  username: widget.connectionInfo.name,
                                );

                          return Column(
                            children: [
                              Expanded(
                                child: _buildMessagesList(
                                  otherLastSeen: otherLastSeen,
                                  otherUser: otherUser,
                                ),
                              ),
                              if (otherIsTyping)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '${otherUser.username} is typing',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey),
                                    ),
                                  ),
                                ),
                            ],
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
    bool removeMedia = false;

    final result = await showDialog<({String text, bool removeMedia})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit message'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Message',
                  ),
                  maxLines: null,
                  autofocus: true,
                ),
                if (msg.hasMedia) ...[
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Remove media'),
                    value: removeMedia,
                    onChanged: (v) {
                      setDialogState(() => removeMedia = v ?? false);
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                (text: controller.text.trim(), removeMedia: removeMedia),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final newText = result.text;
    final textChanged = newText != msg.text;

    if (!textChanged && !removeMedia) return;

    try {
      await _firestoreService.updateMessage(
        connectionId: widget.connectionInfo.connectionId,
        messageId: msg.id,
        newText: newText,
        oldMediaPath: removeMedia && msg.mediaPath != null ? msg.mediaPath : null,
      );

      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m.id == msg.id);
          if (i >= 0) {
            _messages[i] = msg.copyWith(
              text: newText,
              clearMedia: removeMedia,
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
            crossAxisAlignment: isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? _myBubbleColor : _otherBubbleColor,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.hasMedia && msg.mediaUrl != null && msg.mediaType != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: MediaMessageContent(
                              mediaUrl: msg.mediaUrl!,
                              mediaType: msg.mediaType!,
                            ),
                          ),
                        if (msg.text.isNotEmpty)
                          Text(
                            msg.text,
                            style: const TextStyle(
                              color: _bubbleTextColor,
                              fontSize: 16,
                            ),
                          ),
                      ],
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
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
          IconButton(
            onPressed: _isSending ? null : _pickAndSendMedia,
            icon: const Icon(Icons.attach_file),
            tooltip: 'Attach photo or video',
          ),
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
              onChanged: (_) => _onTyping(),
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

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({
    required this.firestoreService,
    required this.typingUserIds,
  });

  final FirestoreService firestoreService;
  final List<String> typingUserIds;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> {
  Map<String, String>? _usernames;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadUsernames();
  }

  @override
  void didUpdateWidget(_TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.typingUserIds != widget.typingUserIds) {
      _loadUsernames();
    }
  }

  Future<void> _loadUsernames() async {
    final map = await widget.firestoreService.getUsernamesForUsers(
      widget.typingUserIds,
    );
    if (mounted) {
      setState(() {
        _usernames = map;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _usernames == null || widget.typingUserIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final names = widget.typingUserIds
        .map((id) => _usernames![id] ?? id)
        .toList();
    final text = names.length == 1
        ? '${names[0]} is typing'
        : '${names.join(', ')} are typing';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ),
    );
  }
}

class _ChatParticipantTile extends StatelessWidget {
  const _ChatParticipantTile({
    required this.userId,
    required this.firestoreService,
    required this.isCurrentUser,
  });

  final String userId;
  final FirestoreService firestoreService;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: firestoreService.getUserProfile(userId),
      builder: (context, snapshot) {
        final user = snapshot.hasData && snapshot.data != null
            ? User.fromFirestore(snapshot.data!, userId)
            : User(userId: userId, email: '', username: userId);

        return ListTile(
          leading: ProfileAvatar(user: user, radius: 24),
          title: Row(
            children: [
              Text(user.username),
              if (isCurrentUser)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '(you)',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                ),
            ],
          ),
          trailing: isCurrentUser
              ? null
              : IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () {
                    Navigator.pop(context);
                    showProfilePopup(context: context, user: user);
                  },
                  tooltip: 'View profile',
                ),
        );
      },
    );
  }
}
