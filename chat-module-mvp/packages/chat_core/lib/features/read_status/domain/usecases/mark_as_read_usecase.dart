import '../repositories/read_status_repository.dart';

class MarkAsReadUseCase {
  MarkAsReadUseCase(this._repository);
  final ReadStatusRepository _repository;

  Future<void> call(String conversationId) =>
      _repository.markAsRead(conversationId);
}
