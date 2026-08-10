import '../repositories/message_repository.dart';

class StopWatchingListMessagesUseCase {
  StopWatchingListMessagesUseCase(this._repository);
  final MessageRepository _repository;

  Future<void> call() => _repository.stopWatchingList();
}
