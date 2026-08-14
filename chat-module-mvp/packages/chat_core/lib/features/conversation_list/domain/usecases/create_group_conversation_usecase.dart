import '../entities/conversation.dart';
import '../repositories/conversation_repository.dart';

class CreateGroupConversationUseCase {
  CreateGroupConversationUseCase(this._repository);
  final ConversationRepository _repository;

  Future<Conversation> call({
    required List<String> participantIds,
    required String roomName,
    String? avatarUrl,
  }) =>
      _repository.createGroupConversation(
        participantIds: participantIds,
        roomName: roomName,
        avatarUrl: avatarUrl,
      );
}
