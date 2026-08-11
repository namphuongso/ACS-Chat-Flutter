import '../repositories/message_repository.dart';

class UpdateMessageUseCase {
  UpdateMessageUseCase(this._repository);
  final MessageRepository _repository;

  Future<bool> call({
    required String roomId,
    required String threadId,
    required String messageId,
    required String content,
  }) =>
      _repository.updateMessage(
        roomId: roomId,
        threadId: threadId,
        messageId: messageId,
        content: content,
      );
}