import '../repositories/conversation_repository.dart';

class SetRoleAdminUseCase {
  SetRoleAdminUseCase(this._repository);
  final ConversationRepository _repository;

  Future<bool> call({
    required String roomId,
    required String userId,
    required bool admin,
  }) =>
      _repository.setRoleAdmin(
        roomId: roomId,
        userId: userId,
        admin: admin,
      );
}
