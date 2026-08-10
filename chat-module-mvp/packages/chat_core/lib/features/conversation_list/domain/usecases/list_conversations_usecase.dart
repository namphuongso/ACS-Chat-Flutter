import '../entities/conversation.dart';
import '../repositories/conversation_repository.dart';

class ListConversationsUseCase {
  ListConversationsUseCase(this._repository);
  final ConversationRepository _repository;

  Future<PaginatedResult<Conversation>> call(
          {String? cursor, int limit = 20}) =>
      _repository.listConversations(cursor: cursor, limit: limit);
}
