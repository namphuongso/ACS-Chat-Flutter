import '../../../conversation_list/domain/entities/conversation.dart';
import '../entities/message.dart';
import '../repositories/message_repository.dart';

class ListMessagesUseCase {
  ListMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Future<PaginatedResult<Message>> call({
    required String roomId,
    required String threadId,
    String? startTime,
    String? cursor,
  }) {
    return _repository.listMessages(
        roomId: roomId,
        threadId: threadId,
        startTime: startTime,
        cursor: cursor);
  }
}
