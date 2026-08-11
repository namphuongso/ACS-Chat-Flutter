import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/hive_conversation_local_datasource.dart';
import '../../data/local/hive_identity_store.dart';
import '../../data/local/hive_message_local_datasource.dart';

/// Cache tin nhắn local (Hive) — hiện nhanh khi mở thread, đọc được offline.
/// Box mở lazily trong datasource; nếu Hive chưa init thì cache no-op.
final messageLocalDataSourceProvider =
    Provider<MessageLocalDataSource>((ref) => HiveMessageLocalDataSource());

/// Cache danh sách conversation local (Hive).
final conversationLocalDataSourceProvider =
    Provider<ConversationLocalDataSource>(
        (ref) => HiveConversationLocalDataSource());

/// Lưu acsUserId của bản thân (mọi room dùng chung) để khôi phục nhanh
/// khi mở chat, không phải chờ join-room mới biết "tôi là ai".
final identityStoreProvider = Provider<HiveIdentityStore>(
    (ref) => HiveIdentityStore());
