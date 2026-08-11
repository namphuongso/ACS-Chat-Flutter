import '../repositories/message_repository.dart';

class DeleteMessageUseCase {
  DeleteMessageUseCase(this._repository);
  final MessageRepository _repository;

  Future<bool> call({
    required String roomId,
    required String threadId,
    required String messageId,
  }) =>
      _repository.deleteMessage(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
      );
}
