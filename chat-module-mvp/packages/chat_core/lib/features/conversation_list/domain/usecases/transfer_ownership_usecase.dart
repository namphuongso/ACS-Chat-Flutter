import '../repositories/conversation_repository.dart';

class TransferOwnershipUseCase {
  TransferOwnershipUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call({
    required String roomId,
    required String toUserId,
  }) =>
      _repository.transferOwnership(
        roomId: roomId,
        toUserId: toUserId,
      );
}
