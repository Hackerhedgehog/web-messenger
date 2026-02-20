import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/connection_info.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';

/// Result passed back when user taps a search result.
class SearchResult {
  const SearchResult({
    required this.message,
    required this.allFetchedMessages,
    this.oldestDoc,
  });
  final Message message;
  final List<Message> allFetchedMessages;
  final DocumentSnapshot? oldestDoc;
}

/// Screen to search messages within a chat.
/// Fetches 20 messages at a time (newest first), filters by search term,
/// and allows loading the next 20 older messages.
class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.currentUser,
    required this.connectionInfo,
  });

  final User currentUser;
  final ConnectionInfo connectionInfo;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();

  final List<Message> _matches = [];
  final List<Message> _allFetchedInSearch = [];
  DocumentSnapshot? _oldestDoc;
  bool _hasMore = true;
  bool _isSearching = false;
  bool _isLoadingOlder = false;
  String? _lastSearchTerm;
  Map<String, String> _senderNames = {};

  static const int _pageSize = 20;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSenderNames(Iterable<String> senderIds) async {
    final ids = senderIds
        .where((id) => id.isNotEmpty && !_senderNames.containsKey(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    final map = await _firestoreService.getUsernamesForUsers(ids);
    if (mounted) {
      setState(() => _senderNames = {..._senderNames, ...map});
    }
  }

  Future<void> _runSearch({bool loadOlder = false}) async {
    final term = _searchController.text.trim();
    if (term.isEmpty) return;

    if (!loadOlder) {
      setState(() {
        _matches.clear();
        _allFetchedInSearch.clear();
        _oldestDoc = null;
        _hasMore = true;
        _lastSearchTerm = term;
        _isSearching = true;
      });
    } else {
      if (_oldestDoc == null || !_hasMore || _isLoadingOlder) return;
      setState(() => _isLoadingOlder = true);
    }

    try {
      final result = await _firestoreService.getMessagesPage(
        connectionId: widget.connectionInfo.connectionId,
        limit: _pageSize,
        startAfterDoc: loadOlder ? _oldestDoc : null,
      );

      if (!mounted) return;

      final lower = term.toLowerCase();
      final batchMatches = result.messages
          .where((m) => m.text.toLowerCase().contains(lower))
          .toList();

      setState(() {
        _isSearching = false;
        _isLoadingOlder = false;
        if (!loadOlder) {
          _matches.clear();
          _senderNames = {widget.currentUser.userId: widget.currentUser.username};
          _allFetchedInSearch
            ..clear()
            ..addAll(result.messages.reversed);
        } else {
          _allFetchedInSearch.insertAll(0, result.messages.reversed);
        }
        _matches.addAll(batchMatches);
        _oldestDoc = result.oldestDoc;
        _hasMore = result.messages.length >= _pageSize;
      });

      await _loadSenderNames(_matches.map((m) => m.senderId));
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _isLoadingOlder = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search failed: $e'),
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
        title: Text('Search in ${widget.connectionInfo.name}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Search messages...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSearching
                      ? null
                      : () => _runSearch(),
                  icon: _isSearching
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.search),
                  tooltip: 'Search',
                ),
              ],
            ),
          ),
          Expanded(
            child: _lastSearchTerm == null
                ? const Center(
                    child: Text(
                      'Enter a search term and tap Search',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : _matches.isEmpty && !_isSearching
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No messages match "$_lastSearchTerm"',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_hasMore && _oldestDoc != null) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _isLoadingOlder
                                    ? null
                                    : () => _runSearch(loadOlder: true),
                                icon: _isLoadingOlder
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.expand_less, size: 20),
                                label: const Text('Search older messages'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _matches.length +
                            (_hasMore && _oldestDoc != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _matches.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: FilledButton.icon(
                                  onPressed: _isLoadingOlder
                                      ? null
                                      : () => _runSearch(loadOlder: true),
                                  icon: _isLoadingOlder
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.expand_less, size: 20),
                                  label: const Text('Search older messages'),
                                ),
                              ),
                            );
                          }
                          final msg = _matches[index];
                          final senderName = _senderNames[msg.senderId] ??
                              (msg.senderId == widget.currentUser.userId
                                  ? widget.currentUser.username
                                  : msg.senderId);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => Navigator.of(context).pop(SearchResult(
          message: msg,
          allFetchedMessages: List.from(_allFetchedInSearch),
          oldestDoc: _oldestDoc,
        )),
                              title: Text(
                                msg.text.isEmpty
                                    ? '(media)'
                                    : msg.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '$senderName · ${_formatDate(msg.createdAt)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
