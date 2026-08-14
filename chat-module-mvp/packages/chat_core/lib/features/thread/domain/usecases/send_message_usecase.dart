import '../entities/message.dart';
import '../repositories/message_repository.dart';

class SendMessageUseCase {
  SendMessageUseCase(this._repository);
  final MessageRepository _repository;

  Future<Message> call({
    required String roomId,
    required String threadId,
    required String content,
    Map<String, dynamic>? metaData,
  }) =>
      _repository.sendMessage(
        roomId: roomId,
        threadId: threadId,
        content: content,
        metaData: metaData,
      );
}
