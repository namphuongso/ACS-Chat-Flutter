import '../../../conversation_list/domain/entities/conversation.dart';
import '../entities/message_resource.dart';
import '../repositories/message_repository.dart';

class GetMessageResourcesUseCase {
  const GetMessageResourcesUseCase(this._repository);

  final MessageRepository _repository;

  Future<PaginatedResult<MessageResource>> call({
    required String roomId,
    required MessageResourceType resourceType,
    int pageIndex = 1,
    int pageSize = 50,
    String? keyword,
  }) {
    return _repository.getMessageResources(
      roomId: roomId,
      resourceType: resourceType,
      pageIndex: pageIndex,
      pageSize: pageSize,
      keyword: keyword,
    );
  }
}
