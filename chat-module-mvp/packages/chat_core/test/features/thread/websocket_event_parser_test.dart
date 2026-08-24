import 'package:chat_core/chat_core.dart';
import 'package:chat_core/features/thread/data/datasources/websocket_event_parser.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketEventParser Tests', () {
    test('parses MessageReacted event correctly', () {
      final json = {
        'type': 'room_event',
        'success': true,
        'roomId': 'room_123',
        'eventType': 'MessageReacted',
        'payload': {
          'messageId': 'msg_456',
          'reactionCode': 'wow',
          'actorId': 'user_789',
          'actorName': 'Hiếu Trần Trọng',
        },
      };

      final message = WebSocketEventParser.parseRoomEvent(json);

      expect(message, isNotNull);
      expect(message!.type, equals(MessageType.reactionUpdate));
      expect(message.content, equals('wow'));
      expect(message.senderId, equals('user_789'));
      expect(message.senderDisplayName, equals('Hiếu Trần Trọng'));
      expect(message.metadata?['targetMessageId'], equals('msg_456'));
    });

    test('parses MessagePinned event correctly', () {
      final json = {
        'type': 'room_event',
        'roomId': 'room_123',
        'eventType': 'MessagePinned',
        'payload': {
          'messageId': 'msg_789',
          'actorId': 'user_000',
          'actorName': 'Admin',
        },
      };

      final message = WebSocketEventParser.parseRoomEvent(json);

      expect(message, isNotNull);
      expect(message!.type, equals(MessageType.messagePinUpdate));
      expect(message.id, equals('msg_789'));
      expect(message.pin, isTrue);
      expect(message.content, equals('pin'));
    });

    test('parses MessageDeleted event correctly', () {
      final json = {
        'type': 'room_event',
        'roomId': 'room_123',
        'eventType': 'MessageDeleted',
        'payload': {
          'messageId': 'msg_999',
          'deletedBy': 'user_111',
        },
      };

      final message = WebSocketEventParser.parseRoomEvent(json);

      expect(message, isNotNull);
      expect(message!.id, equals('msg_999'));
      expect(message.deletedOn, isNotNull);
      expect(message.content, equals('(Tin nhắn đã bị xoá)'));
    });

    test('parses RoomUpdated event correctly', () {
      final json = {
        'type': 'room_event',
        'roomId': 'room_123',
        'eventType': 'RoomUpdated',
        'payload': {
          'roomName': 'LilVan111',
          'actorId': 'user_123',
          'actorName': 'Thái Đăng',
          'isNameChanged': true,
        },
      };

      final message = WebSocketEventParser.parseRoomEvent(json);

      expect(message, isNotNull);
      expect(message!.type, equals(MessageType.system));
      expect(message.content, contains('Thái Đăng'));
      expect(message.content, contains('LilVan111'));
    });
  });
}
