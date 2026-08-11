import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

class _MockAuthTokenRemote implements AuthTokenRemoteDataSource {
  int fetchCalls = 0;
  bool throwOnFetch = false;

  @override
  Future<ChatAccessTokenModel> fetchToken(String roomId) async {
    fetchCalls++;
    if (throwOnFetch) throw Exception('network down');
    return ChatAccessTokenModel(
      token: 'jwt-$roomId',
      expiresOn: DateTime.now().add(const Duration(hours: 1)),
      acsUserId: '8:acs:user-$roomId',
    );
  }

  @override
  void dispose() {}
}

void main() {
  group('AuthTokenRepositoryImpl', () {
    test('getAccessToken hoàn thành và cache token', () async {
      final ds = _MockAuthTokenRemote();
      final repo = AuthTokenRepositoryImpl(ds);

      final token = await repo.getAccessToken('roomA').timeout(
            const Duration(seconds: 2),
          );

      expect(token.token, 'jwt-roomA');
      expect(ds.fetchCalls, 1);
      // Lần 2 không gọi lại datasource (cache trong RAM).
      final again = await repo.getAccessToken('roomA');
      expect(again.token, 'jwt-roomA');
      expect(ds.fetchCalls, 1);
    });

    test('nhiều caller đồng thời dùng chung 1 request (dedup)', () async {
      final ds = _MockAuthTokenRemote();
      final repo = AuthTokenRepositoryImpl(ds);

      final results = await Future.wait([
        repo.getAccessToken('roomA').timeout(const Duration(seconds: 2)),
        repo.getAccessToken('roomA').timeout(const Duration(seconds: 2)),
        repo.getAccessToken('roomA').timeout(const Duration(seconds: 2)),
      ]);

      expect(results.map((t) => t.token), everyElement('jwt-roomA'));
      expect(ds.fetchCalls, 1);
    });

    test('không kẹt khi fetch fail — trả lỗi cho caller', () async {
      final ds = _MockAuthTokenRemote()..throwOnFetch = true;
      final repo = AuthTokenRepositoryImpl(ds);

      await expectLater(
        repo.getAccessToken('roomA').timeout(const Duration(seconds: 2)),
        throwsException,
      );
    });
  });
}
