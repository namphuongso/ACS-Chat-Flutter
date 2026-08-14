import '../repositories/conversation_repository.dart';

class UploadRoomAvatarUseCase {
  UploadRoomAvatarUseCase(this._repository);

  final ConversationRepository _repository;

  Future<String> call({
    required String filePath,
    required String filename,
  }) =>
      _repository.uploadRoomAvatar(filePath: filePath, filename: filename);
}
