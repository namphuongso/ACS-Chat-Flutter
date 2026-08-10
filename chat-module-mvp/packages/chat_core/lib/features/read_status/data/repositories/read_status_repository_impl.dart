import '../../domain/repositories/read_status_repository.dart';
import '../datasources/read_status_remote_datasource.dart';

class ReadStatusRepositoryImpl implements ReadStatusRepository {
  ReadStatusRepositoryImpl(this._dataSource);

  final ReadStatusRemoteDataSource _dataSource;

  @override
  Future<void> markAsRead(String conversationId) =>
      _dataSource.markAsRead(conversationId);

  void dispose() => _dataSource.dispose();
}
