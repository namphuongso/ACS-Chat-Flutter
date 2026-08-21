import 'package:chat_ui/chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatDeepLinkData Tests', () {
    test('fromMap với camelCase roomId & threadId hợp lệ', () {
      final payload = {
        'roomId': 'room_123',
        'threadId': 'thread_456',
        'roomName': 'Nhóm Dev',
      };
      final data = ChatDeepLinkData.fromMap(payload);

      expect(data, isNotNull);
      expect(data!.roomId, 'room_123');
      expect(data.threadId, 'thread_456');
      expect(data.roomName, 'Nhóm Dev');
    });

    test('fromMap với snake_case room_id & thread_id', () {
      final payload = {
        'room_id': 'room_abc',
        'thread_id': 'thread_xyz',
      };
      final data = ChatDeepLinkData.fromMap(payload);

      expect(data, isNotNull);
      expect(data!.roomId, 'room_abc');
      expect(data.threadId, 'thread_xyz');
    });

    test('fromMap với PascalCase RoomId', () {
      final payload = {
        'RoomId': 'room_pascal',
      };
      final data = ChatDeepLinkData.fromMap(payload);

      expect(data, isNotNull);
      expect(data!.roomId, 'room_pascal');
      expect(data.threadId, 'room_pascal');
    });

    test('fromMap trả về null khi payload rỗng hoặc thiếu thông tin phòng', () {
      expect(ChatDeepLinkData.fromMap(null), isNull);
      expect(ChatDeepLinkData.fromMap({}), isNull);
      expect(ChatDeepLinkData.fromMap({'otherField': 'value'}), isNull);
    });
  });
}
