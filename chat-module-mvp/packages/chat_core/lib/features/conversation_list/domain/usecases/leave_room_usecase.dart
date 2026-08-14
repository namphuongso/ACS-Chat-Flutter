import '../repositories/conversation_repository.dart';

class LeaveRoomUseCase {
  LeaveRoomUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call({
    required String roomId,
    String? newAdminUserId,
  }) =>
      _repository.leaveRoom(
        roomId: roomId,
        newAdminUserId: newAdminUserId,
      );
}
