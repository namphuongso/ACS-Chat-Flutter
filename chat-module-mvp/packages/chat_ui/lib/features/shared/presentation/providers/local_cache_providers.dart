import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/hive_conversation_local_datasource.dart';
import '../../data/local/hive_identity_store.dart';
import '../../data/local/hive_message_local_datasource.dart';
import '../../../thread/presentation/providers/thread_providers.dart';

/// Cache tin nhắn local (Hive) — hiện nhanh khi mở thread, đọc được offline.
/// Box mở lazily trong datasource; nếu Hive chưa init thì cache no-op.
final messageLocalDataSourceProvider = Provider<MessageLocalDataSource>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return HiveMessageLocalDataSource(userId: userId);
});

/// Cache danh sách conversation local (Hive).
final conversationLocalDataSourceProvider =
    Provider<ConversationLocalDataSource>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  return HiveConversationLocalDataSource(userId: userId);
});

/// Lưu acsUserId của bản thân (mọi room dùng chung) để khôi phục nhanh
/// khi mở chat, không phải chờ join-room mới biết "tôi là ai".
final identityStoreProvider =
    Provider<HiveIdentityStore>((ref) => HiveIdentityStore());

/// Hàm tiện ích public hỗ trợ Host app xóa sạch dữ liệu cache của user khi Logout
Future<void> clearChatModuleUserData(String userId) async {
  await HiveMessageLocalDataSource().clearAllUserData(userId);
  await HiveConversationLocalDataSource().clearUserData(userId);
  await HiveIdentityStore().clearUserData(userId);
}
