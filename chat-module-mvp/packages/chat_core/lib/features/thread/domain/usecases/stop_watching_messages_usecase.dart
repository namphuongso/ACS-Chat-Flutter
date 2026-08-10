import '../repositories/message_repository.dart';

class StopWatchingMessagesUseCase {
  StopWatchingMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Future<void> call(String threadId) => _repository.stopWatching(threadId);
}
