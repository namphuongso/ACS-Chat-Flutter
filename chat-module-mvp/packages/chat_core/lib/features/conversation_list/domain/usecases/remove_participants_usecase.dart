import '../repositories/conversation_repository.dart';

class RemoveParticipantsUseCase {
  RemoveParticipantsUseCase(this._repository);
  final ConversationRepository _repository;

  Future<int> call({
    required String roomId,
    required List<String> participantIds,
  }) =>
      _repository.removeParticipants(
        roomId: roomId,
        participantIds: participantIds,
      );
}
