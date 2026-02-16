import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a group invite received by a user.
/// groupInvites in user doc is `Map<groupId, timestamp>`. Connection details
/// (name, creatorId) are fetched from connections/{groupId}.
class GroupInviteInfo {
  const GroupInviteInfo({
    required this.groupId,
    required this.creatorId,
    required this.groupName,
    required this.participantIds,
    this.timestamp,
  });

  final String groupId;
  final String creatorId;
  final String groupName;
  final List<String> participantIds;
  final DateTime? timestamp;

  factory GroupInviteInfo.fromConnection(
    String groupId,
    Map<String, dynamic> connData,
    Timestamp? inviteTimestamp,
  ) {
    return GroupInviteInfo(
      groupId: groupId,
      creatorId: connData['creatorId'] as String? ?? '',
      groupName: connData['name'] as String? ?? 'Unnamed group',
      participantIds: const [],
      timestamp: inviteTimestamp?.toDate(),
    );
  }
}
