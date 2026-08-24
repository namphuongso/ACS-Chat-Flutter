import 'package:chat_core/chat_core.dart';
import 'package:chat_ui/features/thread/presentation/notifiers/thread_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThreadState Initial State Tests', () {
    test('initial ThreadState has empty messages and hasMore is true', () {
      final state = ThreadState();
      expect(state.messages, isEmpty);
      expect(state.historyLoaded, isFalse);
      expect(state.hasMore, isTrue);
    });

    test('ThreadState copyWith updates messages list correctly', () {
      final message = Message(
        id: 'msg-1',
        threadId: 'thread-1',
        senderId: 'user-1',
        senderDisplayName: 'User 1',
        content: 'Hello',
        type: MessageType.text,
        createdAt: DateTime.now(),
      );

      final initialState = ThreadState();
      final updatedState = initialState.copyWith(messages: [message]);
      expect(updatedState.messages.length, 1);
      expect(updatedState.messages.first.content, 'Hello');
    });
  });
}
