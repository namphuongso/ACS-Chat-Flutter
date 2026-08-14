import '../repositories/conversation_repository.dart';

class UploadFileViaSasUseCase {
  const UploadFileViaSasUseCase(this._repository);

  final ConversationRepository _repository;

  Future<String> call({
    required String filePath,
    required String fileName,
    String? contentType,
    String? documentId,
    void Function(int sent, int total)? onProgress,
  }) {
    return _repository.uploadFileViaSas(
      filePath: filePath,
      fileName: fileName,
      contentType: contentType,
      documentId: documentId,
      onProgress: onProgress,
    );
  }
}
