import '../entities/conversation.dart';
import '../repositories/conversation_repository.dart';

class GetConversationUseCase {
  GetConversationUseCase(this._repository);
  final ConversationRepository _repository;

  Future<Conversation> call(String conversationId) =>
      _repository.getConversation(conversationId);
}
