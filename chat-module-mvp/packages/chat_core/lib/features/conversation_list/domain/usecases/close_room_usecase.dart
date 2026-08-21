import '../repositories/conversation_repository.dart';

/// Đóng (khóa) room — giải tán nhóm chat (API docs mục 23, `close-room`).
class CloseRoomUseCase {
  CloseRoomUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call({required String roomId}) =>
      _repository.closeRoom(roomId: roomId);
}
