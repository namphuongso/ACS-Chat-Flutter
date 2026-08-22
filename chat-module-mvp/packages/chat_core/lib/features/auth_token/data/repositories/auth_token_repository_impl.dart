import '../../../../core/error/chat_api_exception.dart';
import '../../../../core/utils/chat_logger.dart';
import '../../domain/entities/chat_access_token.dart';
import '../../domain/repositories/auth_token_repository.dart';
import '../datasources/auth_token_remote_datasource.dart';

class AuthTokenRepositoryImpl implements AuthTokenRepository {
  AuthTokenRepositoryImpl(this._dataSource);

  final AuthTokenRemoteDataSource _dataSource;

  final Map<String, ChatAccessToken> _cached = {};
  final Map<String, Future<ChatAccessToken>> _inFlight = {};

  @override
  Future<ChatAccessToken> getAccessToken(String roomId) {
    final cached = _cached[roomId];
    if (cached != null && !cached.needsRefresh) {
      return Future.value(cached);
    }
    return _inFlight[roomId] ??= _refresh(roomId).whenComplete(() {
      _inFlight.remove(roomId);
    });
  }

  @override
  ChatAccessToken? getCachedToken(String roomId) {
    final cached = _cached[roomId];
    if (cached != null && !cached.needsRefresh) {
      return cached;
    }
    return null;
  }

  @override
  Future<void> refresh(String roomId) async {
    _cached.remove(roomId);
    await getAccessToken(roomId);
  }

  @override
  Future<void> clear(String roomId) async {
    _cached.remove(roomId);
  }

  @override
  Future<void> dispose() async {
    _dataSource.dispose();
    _cached.clear();
    _inFlight.clear();
  }

  @override
  void cacheToken(String roomId, ChatAccessToken token) {
    _cached[roomId] = token;
  }

  Future<ChatAccessToken> _refresh(String roomId) async {
    int retries = 3;
    while (true) {
      try {
        final token = await _dataSource.fetchToken(roomId);
        _cached[roomId] = token;
        return token;
      } catch (e) {
        ChatLogger.error('join-room attempt failed (roomId=$roomId)', error: e);
        if (e is ChatApiException &&
            (e.statusCode == 401 ||
                e.statusCode == 403 ||
                e.statusCode == 404)) {
          rethrow;
        }
        retries--;
        if (retries <= 0) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
  }
}
