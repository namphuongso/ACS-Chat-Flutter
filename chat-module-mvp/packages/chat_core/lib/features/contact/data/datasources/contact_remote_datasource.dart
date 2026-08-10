import '../../../../core/domain/entities/chat_user.dart';
import '../../../conversation_list/domain/entities/conversation.dart';

abstract class ContactRemoteDataSource {
  Future<PaginatedResult<ChatUser>> searchContacts({
    String? keyword,
    int pageIndex = 0,
    int pageSize = 15,
  });
}
