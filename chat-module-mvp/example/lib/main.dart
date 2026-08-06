import 'package:chat_core/chat_core.dart';
import 'package:chat_ui/chat_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stub demo — app thật thay bằng cách lấy JWT từ hệ thống auth của
/// chính app (Firebase Auth, Auth0, session cookie...). Module chat
/// không quan tâm cách app đăng nhập, chỉ cần interface này.
class DemoAppTokenProvider implements ChatAuthTokenProvider {
  @override
  Future<String> getAppToken() async {
    // TODO: thay bằng token thật khi test với BE thật.
    return 'demo-app-jwt-token';
  }
}

void main() {
  runApp(
    ProviderScope(
      overrides: [
        chatModuleConfigProvider.overrideWithValue(
          const ChatModuleConfig(
            backendBaseUrl: 'https://api.example.com/api', // TODO: đổi URL BE thật
          ),
        ),
        chatAuthTokenProviderProvider.overrideWithValue(DemoAppTokenProvider()),
      ],
      child: const ChatExampleApp(),
    ),
  );
}

class ChatExampleApp extends StatelessWidget {
  const ChatExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat Module Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const ConversationListScreen(),
    );
  }
}

/// currentUserId dùng để phân biệt tin của mình vs người khác trong UI
/// (MessageBubble.isMe, ConversationList lọc participant "người kia").
/// App thật lấy từ chatRepositoryProvider.getAccessToken() sau khi login.
const _demoCurrentUserId = 'app-user-123';

class ConversationListScreen extends StatelessWidget {
  const ConversationListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tin nhắn')),
      body: ConversationList(
        currentUserId: _demoCurrentUserId,
        onTapConversation: (conversation) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ThreadScreen(
                threadId: conversation.threadId,
                title: conversation.participants
                    .where((p) => p.id != _demoCurrentUserId)
                    .map((p) => p.displayName)
                    .join(', '),
                currentUserId: _demoCurrentUserId,
              ),
            ),
          );
        },
      ),
    );
  }
}
