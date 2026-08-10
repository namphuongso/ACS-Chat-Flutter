import '../entities/conversation.dart';
import '../repositories/conversation_repository.dart';

class GetOrCreateDirectConversationUseCase {
  GetOrCreateDirectConversationUseCase(this._repository);
  final ConversationRepository _repository;

  Future<Conversation> call(String otherUserId) =>
      _repository.getOrCreateDirectConversation(otherUserId);
}
