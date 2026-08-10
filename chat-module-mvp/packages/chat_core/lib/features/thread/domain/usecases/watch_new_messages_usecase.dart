import '../entities/message.dart';
import '../repositories/message_repository.dart';

class WatchNewMessagesUseCase {
  WatchNewMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Stream<Message> call(String roomId, String threadId) {
    return _repository.watchNewMessages(roomId, threadId);
  }
}
