import '../repositories/conversation_repository.dart';

class AddParticipantsUseCase {
  AddParticipantsUseCase(this._repository);
  final ConversationRepository _repository;

  Future<int> call({
    required String roomId,
    required List<String> participantIds,
  }) =>
      _repository.addParticipants(
        roomId: roomId,
        participantIds: participantIds,
      );
}
