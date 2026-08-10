import '../entities/message.dart';
import '../repositories/message_repository.dart';

class WatchListMessagesUseCase {
  WatchListMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Stream<Message> call(String roomId) => _repository.watchListMessages(roomId);
}
