import '../../../../core/domain/entities/chat_member.dart';
import '../repositories/conversation_repository.dart';

class GetMembersUseCase {
  GetMembersUseCase(this._repository);
  final ConversationRepository _repository;

  Future<List<ChatMember>> call(String roomId) =>
      _repository.getMembers(roomId);
}
