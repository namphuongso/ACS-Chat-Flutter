import '../entities/room_update_type.dart';
import '../repositories/conversation_repository.dart';

class GetRoomUpdateTypesUseCase {
  const GetRoomUpdateTypesUseCase(this._repository);

  final ConversationRepository _repository;

  Future<List<RoomUpdateType>> call() => _repository.getRoomUpdateTypes();
}
