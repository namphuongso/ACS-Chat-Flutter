import 'package:chat_core/chat_core.dart';
import 'package:chat_core/chat_core_impl.dart';
import 'package:chat_core/features/thread/data/datasources/websocket_event_dispatcher.dart';
import 'package:test/test.dart';

void main() {
  group('WebSocketEventDispatcher Tests', () {
    late WebSocketEventDispatcher dispatcher;

    setUp(() {
      dispatcher = WebSocketEventDispatcher();
    });

    tearDown(() async {
      await dispatcher.dispose();
    });

    test('deduplicates regular text messages by ID', () async {
      final messages = <Message>[];
      final sub = dispatcher.watchNewMessages('thread_1').listen(messages.add);

      final msg1 = MessageModel(
        id: 'msg_1',
        threadId: 'thread_1',
        senderId: 'user_1',
        senderDisplayName: 'User 1',
        content: 'Hello',
        type: MessageType.text,
        createdAt: DateTime.now(),
      );

      dispatcher.emit(msg1);
      dispatcher.emit(msg1); // Duplicate

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(messages.length, equals(1));
      await sub.cancel();
    });

    test('bypasses deduplication for reaction updates', () async {
      final messages = <Message>[];
      final sub = dispatcher.watchNewMessages('thread_1').listen(messages.add);

      final react1 = MessageModel(
        id: 'react_msg1_user1_heart_123',
        threadId: 'thread_1',
        senderId: 'user_1',
        senderDisplayName: 'User 1',
        content: 'heart',
        type: MessageType.reactionUpdate,
        createdAt: DateTime.now(),
      );

      final react2 = MessageModel(
        id: 'react_msg1_user1_wow_456',
        threadId: 'thread_1',
        senderId: 'user_1',
        senderDisplayName: 'User 1',
        content: 'wow',
        type: MessageType.reactionUpdate,
        createdAt: DateTime.now(),
      );

      dispatcher.emit(react1);
      dispatcher.emit(react2); // Second reaction change on same message

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(messages.length, equals(2));
      await sub.cancel();
    });

    test('evicts oldest entries when LRU queue capacity exceeds 100', () async {
      for (int i = 0; i < 105; i++) {
        dispatcher.emit(MessageModel(
          id: 'msg_$i',
          threadId: 'thread_1',
          senderId: 'user_1',
          senderDisplayName: 'User 1',
          content: 'Message $i',
          type: MessageType.text,
          createdAt: DateTime.now(),
        ));
      }

      // msg_0 should be evicted from LRU set after 100 new items
      // Emitting msg_0 again should now succeed
      final messages = <Message>[];
      final sub = dispatcher.watchNewMessages('thread_1').listen(messages.add);

      dispatcher.emit(MessageModel(
        id: 'msg_0',
        threadId: 'thread_1',
        senderId: 'user_1',
        senderDisplayName: 'User 1',
        content: 'Message 0 re-emitted',
        type: MessageType.text,
        createdAt: DateTime.now(),
      ));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(messages.length, equals(1));
      await sub.cancel();
    });
  });
}
