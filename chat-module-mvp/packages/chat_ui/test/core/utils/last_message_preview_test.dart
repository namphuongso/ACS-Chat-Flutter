import 'package:chat_core/chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../lib/core/utils/last_message_preview.dart';

void main() {
  const me = ChatUser(
    id: 'me',
    displayName: 'Nguyen Van A',
    acsUserId: 'acs-me',
  );
  const other = ChatUser(id: 'other', displayName: 'Tran Van B');

  Conversation conversationWith(ConversationSummary summary) => Conversation(
        id: 'room',
        threadId: 'thread',
        type: ConversationType.direct,
        participants: const [me, other],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        roomName: 'Tran Van B',
        lastMessage: summary,
      );

  test('does not prefix a message sent by the other participant', () {
    final conversation = conversationWith(
      ConversationSummary(
        content: 'Xin chao',
        senderDisplayName: 'Nguoi Moi',
        senderId: 'other',
        createdAt: DateTime(2026),
      ),
    );

    expect(LastMessagePreview.format(conversation), 'Xin chao');
  });

  test('prefixes own realtime message using ACS sender id', () {
    final conversation = conversationWith(
      ConversationSummary(
        content: 'Xin chao',
        senderDisplayName: '',
        senderId: 'acs-me',
        createdAt: DateTime(2026),
      ),
    );

    expect(LastMessagePreview.format(conversation), 'Xin chao');
  });

  test('prefixes own message when current user is absent from participants', () {
    final conversation = Conversation(
      id: 'room',
      threadId: 'thread',
      type: ConversationType.direct,
      participants: const [other],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      lastMessage: ConversationSummary(
        content: 'Xin chao',
        senderDisplayName: '',
        senderId: '8:acs:acs-me',
        createdAt: DateTime(2026),
      ),
    );

    expect(
      LastMessagePreview.format(conversation),
      'Xin chao',
    );
  });

  test('uses current user display name for legacy room summary', () {
    final conversation = conversationWith(
      ConversationSummary(
        content: 'Xin chao',
        senderDisplayName: 'Nguyen Van A',
        createdAt: DateTime(2026),
      ),
    );

    expect(LastMessagePreview.format(conversation), 'Xin chao');
  });

  test('strips HTML tags and unescapes entities for last message preview', () {
    final conversation = conversationWith(
      ConversationSummary(
        content:
            '<b><font size="3">11</font></b><div><i><font size="3">22</font></i></div>',
        senderDisplayName: 'Nguyen Van A',
        createdAt: DateTime(2026),
      ),
    );

    expect(LastMessagePreview.format(conversation), '11 22');
  });
}
