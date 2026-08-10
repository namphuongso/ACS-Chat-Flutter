import '../repositories/message_repository.dart';

class PinMessageUseCase {
  PinMessageUseCase(this._repository);
  final MessageRepository _repository;

  Future<bool> call({
    required String threadId,
    required String messageId,
    required bool pin,
  }) =>
      _repository.pinMessage(
        threadId: threadId,
        messageId: messageId,
        pin: pin,
      );
}
