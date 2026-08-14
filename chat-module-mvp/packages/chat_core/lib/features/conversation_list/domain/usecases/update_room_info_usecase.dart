import '../repositories/conversation_repository.dart';

class UpdateRoomInfoUseCase {
  UpdateRoomInfoUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call({
    required String roomId,
    required String roomName,
    String? avatarUrl,
    required String roomType,
  }) =>
      _repository.updateRoomInfo(
        roomId: roomId,
        roomName: roomName,
        avatarUrl: avatarUrl,
        roomType: roomType,
      );
}
