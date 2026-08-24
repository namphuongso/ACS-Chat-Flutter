/// Nguồn duy nhất sinh nội dung hiển thị cho tin sự kiện hệ thống trong
/// phòng chat (đổi tên nhóm, thêm/xoá thành viên, phong Admin...).
///
/// Dùng chung cho cả 3 nguồn dữ liệu:
/// - REST history (`MessageModel.fromAcsJson`).
/// - Realtime signal (`NativeRealtimeDataSourceImpl` → notifier).
/// - Làm giàu tin lịch sử thiếu text (`_enrichSystemMessageContent`).
///
/// Tên người tham gia được resolve theo chuỗi fallback field khác nhau tuỳ
/// backend; caller có thể truyền thêm fallback đã resolve từ state phòng
/// (vd `_getDisplayName`) qua [actorFallback]/[targetFallback].
typedef SystemMessageCustomResolver = String? Function({
  required String eventType,
  Map<String, dynamic> json,
  Map<String, dynamic> payload,
  String actorFallback,
  String targetFallback,
  List<String> joinedUserFallbacks,
  bool isSelfRemoved,
});

class SystemMessageTextBuilder {
  const SystemMessageTextBuilder._();

  /// Hook tuỳ biến ngôn ngữ / bản dịch chuỗi thông báo hệ thống từ host app.
  static SystemMessageCustomResolver? customResolver;

  /// Đặt custom resolver hỗ trợ host app thiết lập bản dịch thông báo hệ thống.
  static void setCustomResolver(SystemMessageCustomResolver? resolver) {
    customResolver = resolver;
  }

  /// Sinh câu hiển thị cho [eventType]. Trả về `null` nếu eventType không
  /// thuộc loại đã biết (caller tự quyết fallback).
  static String? build({
    required String eventType,
    Map<String, dynamic> json = const {},
    Map<String, dynamic> payload = const {},
    String actorFallback = '',
    String targetFallback = '',
    List<String> joinedUserFallbacks = const [],
    bool isSelfRemoved = false,
  }) {
    if (customResolver != null) {
      final custom = customResolver!(
        eventType: eventType,
        json: json,
        payload: payload,
        actorFallback: actorFallback,
        targetFallback: targetFallback,
        joinedUserFallbacks: joinedUserFallbacks,
        isSelfRemoved: isSelfRemoved,
      );
      if (custom != null) return custom;
    }
    final normalized = eventType.trim().toLowerCase();
    switch (normalized) {
      case 'roomownershiptransferred':
        return _roomOwnershipTransferred(
            json, payload, actorFallback, targetFallback);
      case 'roomrolechanged':
        return _roomRoleChanged(json, payload, actorFallback, targetFallback);
      case 'memberremoved':
        return _memberRemoved(json, payload, actorFallback, targetFallback,
            isSelfRemoved: isSelfRemoved);
      case 'memberjoined':
        return _memberJoined(json, payload, actorFallback, joinedUserFallbacks);
      case 'memberleft':
        return _memberLeft(json, payload, actorFallback, targetFallback);
      case 'roomupdated':
        return _roomUpdated(json, payload, actorFallback);
      case 'roomcreated':
      case 'createroom':
      case 'roomcreate':
        return _roomCreated(json, payload, actorFallback);
      case 'roomdisbanded':
      case 'roomclosed':
      case 'closeroom':
        final actor = _str(json['actorName']) != ''
            ? _str(json['actorName'])
            : _firstTrimmed([
                json['actorDisplayName'],
                payload['actorName'],
                actorFallback,
              ]);
        return actor.isNotEmpty
            ? '**$actor** đã giải tán nhóm'
            : 'Phòng chat đã bị giải tán';
      default:
        return null;
    }
  }

  // --- Từng loại event ---

  static String _roomOwnershipTransferred(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
    String targetFallback,
  ) {
    final actor = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['actorName'],
      payload['transferredByName'],
      payload['changedByName'],
      payload['fromUserName'],
      actorFallback,
    ]);
    final toUserName = _firstTrimmed([
      payload['toUserName'],
      payload['targetName'],
      payload['targetDisplayName'],
      payload['newOwnerName'],
      _nestedName(payload['targetUser']),
      json['toUserName'],
      targetFallback,
    ]);
    if (actor.isNotEmpty && toUserName.isNotEmpty) {
      return '**$actor** đã chuyển quyền Trưởng phòng cho **$toUserName**';
    } else if (toUserName.isNotEmpty) {
      return '**$toUserName** đã trở thành Trưởng phòng mới';
    } else if (actor.isNotEmpty) {
      return '**$actor** đã chuyển quyền Trưởng phòng';
    }
    return 'Quyền Trưởng phòng đã được chuyển giao';
  }

  static String _roomRoleChanged(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
    String targetFallback,
  ) {
    final userName = _firstTrimmed([
      payload['userName'],
      payload['targetName'],
      payload['targetDisplayName'],
      payload['memberName'],
      payload['memberUserName'],
      payload['userDisplayName'],
      payload['toUserName'],
      json['targetName'],
      json['userName'],
      targetFallback,
    ]);
    final actor = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['actorName'],
      payload['changedByName'],
      payload['actorDisplayName'],
      payload['fromUserName'],
      actorFallback,
    ]);
    final isAdmin = payload['isAdmin'] == true ||
        json['isAdmin'] == true ||
        payload['role']?.toString().toLowerCase() == 'admin' ||
        json['role']?.toString().toLowerCase() == 'admin' ||
        payload['newRole']?.toString().toLowerCase() == 'admin' ||
        json['newRole']?.toString().toLowerCase() == 'admin';

    if (actor.isNotEmpty && userName.isNotEmpty) {
      return isAdmin
          ? '**$actor** đã phong **$userName** làm Admin'
          : '**$actor** đã gỡ quyền Admin của **$userName**';
    } else if (userName.isNotEmpty) {
      return isAdmin
          ? '**$userName** đã được phong làm Admin'
          : '**$userName** đã bị gỡ quyền Admin';
    } else if (actor.isNotEmpty) {
      return isAdmin
          ? '**$actor** đã thêm Admin mới'
          : '**$actor** đã gỡ quyền Admin';
    }
    return 'Quyền Admin trong phòng đã thay đổi';
  }

  static String _memberRemoved(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
    String targetFallback, {
    required bool isSelfRemoved,
  }) {
    if (isSelfRemoved) return 'Bạn đã bị xóa khỏi phòng';
    final actorName = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['actorName'],
      payload['actorDisplayName'],
      payload['removedByName'],
      json['removedByName'],
      actorFallback,
    ]);
    final removedUserName = _firstTrimmed([
      payload['removedUserName'],
      payload['removedUserDisplayName'],
      payload['targetName'],
      payload['targetDisplayName'],
      payload['userName'],
      _nestedName(payload['removedUser']),
      json['removedUserName'],
      json['targetName'],
      targetFallback,
    ]);
    if (actorName.isNotEmpty && removedUserName.isNotEmpty) {
      return '**$actorName** đã xóa **$removedUserName** khỏi nhóm';
    } else if (removedUserName.isNotEmpty) {
      return '**$removedUserName** đã bị xóa khỏi nhóm';
    } else if (actorName.isNotEmpty) {
      return '**$actorName** đã xóa một thành viên khỏi nhóm';
    }
    return 'Một thành viên đã bị xóa khỏi nhóm';
  }

  static String _memberJoined(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
    List<String> joinedUserFallbacks,
  ) {
    final actorName = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['actorName'],
      payload['addedByName'],
      json['addedByName'],
      actorFallback,
    ]);
    final addedUsers =
        (payload['addedUsers'] ?? json['addedUsers']) as List? ?? const [];
    final addedNames = addedUsers
        .map((u) => u is Map
            ? _firstTrimmed(
                [u['displayName'], u['userName'], u['userDisplayName']])
            : _str(u).trim())
        .where((n) => n.isNotEmpty)
        .toList();
    final targetNames = addedNames.isNotEmpty
        ? addedNames.join(', ')
        : (joinedUserFallbacks.isNotEmpty
            ? joinedUserFallbacks.join(', ')
            : _firstTrimmed([
                payload['targetName'],
                payload['targetDisplayName'],
                payload['userName'],
                payload['addedUserName'],
                json['targetName'],
                json['userName'],
              ]));

    if (actorName.isNotEmpty && targetNames.isNotEmpty) {
      return '**$actorName** đã thêm **$targetNames** vào nhóm';
    } else if (targetNames.isNotEmpty) {
      return '**$targetNames** đã vào nhóm';
    } else if (actorName.isNotEmpty) {
      return '**$actorName** đã thêm thành viên mới vào nhóm';
    }
    return 'Thành viên mới đã vào nhóm';
  }

  static String _memberLeft(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
    String targetFallback,
  ) {
    final userName = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['userName'],
      payload['targetName'],
      payload['actorDisplayName'],
      actorFallback,
      targetFallback,
    ]);
    return userName.isNotEmpty
        ? '**$userName** đã rời khỏi nhóm'
        : 'Một thành viên đã rời khỏi nhóm';
  }

  static String _roomUpdated(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
  ) {
    final roomName = _firstTrimmed([payload['roomName'], json['roomName']]);
    final actor = _firstTrimmed([
      json['actorName'],
      json['actorDisplayName'],
      payload['actorName'],
      payload['updatedByName'],
      payload['actorDisplayName'],
      json['updatedByName'],
      actorFallback,
    ]);
    final updateType = _firstTrimmed([
      payload['updateType'],
      json['updateType'],
      payload['type'],
      json['type'],
    ]).toLowerCase();

    final isAvatarChanged = updateType.contains('avatar') ||
        (updateType.isEmpty &&
            (payload['isAvatarChanged'] == true ||
                payload['avatarChanged'] == true ||
                payload['isAvatarUpdated'] == true ||
                json['isAvatarChanged'] == true));
    final isNameChanged = updateType.contains('name') ||
        (updateType.isEmpty &&
            (payload['isNameChanged'] == true ||
                payload['nameChanged'] == true ||
                payload['isNameUpdated'] == true ||
                json['isNameChanged'] == true));

    if (isNameChanged && isAvatarChanged) {
      return actor.isNotEmpty
          ? '**$actor** đã đổi tên và ảnh đại diện nhóm'
          : 'Tên và ảnh đại diện nhóm đã được cập nhật';
    } else if (isAvatarChanged) {
      return actor.isNotEmpty
          ? '**$actor** đã cập nhật ảnh đại diện nhóm'
          : 'Ảnh đại diện nhóm đã được cập nhật';
    } else if (isNameChanged) {
      return actor.isNotEmpty
          ? (roomName.isNotEmpty
              ? '**$actor** đã đổi tên nhóm thành **$roomName**'
              : '**$actor** đã đổi tên nhóm')
          : (roomName.isNotEmpty
              ? 'Tên nhóm đã được đổi thành **$roomName**'
              : 'Tên nhóm đã được cập nhật');
    } else if (actor.isNotEmpty) {
      return '**$actor** đã cập nhật thông tin nhóm';
    }
    return 'Thông tin nhóm đã được cập nhật';
  }

  static String _roomCreated(
    Map<String, dynamic> json,
    Map<String, dynamic> payload,
    String actorFallback,
  ) {
    final creatorName = _firstTrimmed([
      json['actorName'],
      payload['actorName'],
      payload['createdByName'],
      _nestedName(payload['createdUser']),
      actorFallback,
    ]);
    final roomName = _firstTrimmed([payload['roomName'], json['roomName']]);
    if (creatorName.isNotEmpty && roomName.isNotEmpty) {
      return '**$creatorName** đã tạo nhóm **$roomName**';
    } else if (creatorName.isNotEmpty) {
      return '**$creatorName** đã tạo nhóm chat';
    } else if (roomName.isNotEmpty) {
      return 'Nhóm **$roomName** đã được tạo';
    }
    return 'Nhóm chat đã được tạo';
  }

  // --- Helpers ---

  static String _str(Object? value) => value?.toString() ?? '';

  /// Lấy chuỗi trim đầu tiên khác rỗng trong [candidates].
  static String _firstTrimmed(List<Object?> candidates) {
    for (final c in candidates) {
      final s = _str(c).trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Lấy displayName/userName từ object lồng nhau (vd `payload['targetUser']`).
  static String _nestedName(Object? value) {
    if (value is Map) {
      return _firstTrimmed([value['displayName'], value['userName']]);
    }
    return '';
  }
}
