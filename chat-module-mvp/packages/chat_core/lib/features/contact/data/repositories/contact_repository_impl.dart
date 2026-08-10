import '../../../../core/domain/entities/chat_user.dart';
import '../../../conversation_list/domain/entities/conversation.dart';
import '../../domain/repositories/contact_repository.dart';
import '../datasources/contact_remote_datasource.dart';

class ContactRepositoryImpl implements ContactRepository {
  ContactRepositoryImpl(this._remoteDataSource);

  final ContactRemoteDataSource _remoteDataSource;

  @override
  Future<PaginatedResult<ChatUser>> searchContacts({
    String? keyword,
    int pageIndex = 0,
    int pageSize = 15,
  }) {
    return _remoteDataSource.searchContacts(
      keyword: keyword,
      pageIndex: pageIndex,
      pageSize: pageSize,
    );
  }
}
