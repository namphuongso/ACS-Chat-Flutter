import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chat_module_example/main.dart';

class MockConversationRepository implements ConversationRepository {
  @override
  Future<Conversation> getOrCreateDirectConversation(String otherUserId) async {
    throw UnimplementedError();
  }

  @override
  Future<PaginatedResult<Conversation>> listConversations({
    String? cursor,
    int limit = 20,
  }) async {
    return const PaginatedResult(items: [], hasMore: false);
  }

  @override
  Future<Conversation> getConversation(String conversationId) async {
    throw UnimplementedError();
  }
}

void main() {
  testWidgets('Chat app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatModuleConfigProvider.overrideWithValue(
            const ChatModuleConfig(
              backendBaseUrl: 'https://api.example.com/api',
            ),
          ),
          chatAuthTokenProviderProvider.overrideWithValue(DemoAppTokenProvider()),
          conversationRepositoryProvider.overrideWithValue(MockConversationRepository()),
        ],
        child: const ChatExampleApp(),
      ),
    );

    expect(find.text('Tin nhắn'), findsOneWidget);
  });
}
