import 'package:test/test.dart';
import 'package:chat_core/chat_core.dart';

void main() {
  group('Message', () {
    test('copyWith giữ nguyên field không đổi, chỉ cập nhật status', () {
      final original = Message(
        id: 'm1',
        threadId: 't1',
        senderId: 'u1',
        senderDisplayName: 'A',
        content: 'hello',
        type: MessageType.text,
        createdAt: DateTime(2026, 1, 1),
        status: MessageDeliveryStatus.sending,
      );

      final updated = original.copyWith(status: MessageDeliveryStatus.sent);

      expect(updated.status, MessageDeliveryStatus.sent);
      expect(updated.content, original.content);
      expect(updated.id, original.id);
    });

    test('hai message cùng id được coi là bằng nhau', () {
      final a = Message(
        id: 'm1',
        threadId: 't1',
        senderId: 'u1',
        senderDisplayName: 'A',
        content: 'a',
        type: MessageType.text,
        createdAt: DateTime(2026, 1, 1),
      );
      final b = Message(
        id: 'm1',
        threadId: 't1',
        senderId: 'u2',
        senderDisplayName: 'B',
        content: 'b khác nội dung',
        type: MessageType.text,
        createdAt: DateTime(2026, 1, 2),
      );
      expect(a, equals(b));
    });
  });

  group('MessageType', () {
    test('fromString trả về unknown cho type lạ (tương thích ngược)', () {
      expect(MessageType.fromString('sticker'), MessageType.unknown);
      expect(MessageType.fromString('text'), MessageType.text);
    });
  });
}
