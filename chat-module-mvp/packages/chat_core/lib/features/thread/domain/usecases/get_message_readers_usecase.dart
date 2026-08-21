import '../entities/message_reader.dart';
import '../repositories/message_repository.dart';

class GetMessageReadersUseCase {
  const GetMessageReadersUseCase(this._repository);

  final MessageRepository _repository;

  Future<List<MessageReader>> call({
    required String roomId,
    required String messageId,
    bool? read,
  }) {
    return _repository.getMessageReaders(
      roomId: roomId,
      messageId: messageId,
      read: read,
    );
  }
}
