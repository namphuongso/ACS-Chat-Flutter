import '../repositories/conversation_repository.dart';

class PinConversationUseCase {
  PinConversationUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call(String conversationId, bool pin) =>
      _repository.pinConversation(conversationId, pin);
}
