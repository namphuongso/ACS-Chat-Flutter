import '../../../../core/domain/entities/chat_user.dart';
import '../../../conversation_list/domain/entities/conversation.dart';
import '../repositories/contact_repository.dart';

class SearchContactsUseCase {
  SearchContactsUseCase(this._repository);
  final ContactRepository _repository;

  Future<PaginatedResult<ChatUser>> call({
    String? keyword,
    int pageIndex = 0,
    int pageSize = 15,
  }) {
    return _repository.searchContacts(
      keyword: keyword,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
  }
}
