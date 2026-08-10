import '../entities/pinned_message.dart';
import '../repositories/message_repository.dart';

class GetPinnedMessagesUseCase {
  GetPinnedMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Future<List<PinnedMessage>> call(String roomId) =>
      _repository.getPinnedMessages(roomId);
}
