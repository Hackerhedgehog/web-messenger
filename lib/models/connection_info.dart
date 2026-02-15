/// Represents a connection (chat) for display in the Chats tab.
/// For 1:1 chats: otherUserId is the other participant, isGroup is false.
/// For group chats: otherUserId is empty, isGroup is true, participantIds has all members.
class ConnectionInfo {
  const ConnectionInfo({
    required this.connectionId,
    required this.otherUserId,
    required this.name,
    required this.lastMessage,
    this.otherParticipantStillConnected = true,
    this.isGroup = false,
    this.participantIds = const [],
  });

  final String connectionId;
  final String otherUserId;
  final String name;
  final DateTime? lastMessage;
  final bool otherParticipantStillConnected;
  final bool isGroup;
  final List<String> participantIds;
}
