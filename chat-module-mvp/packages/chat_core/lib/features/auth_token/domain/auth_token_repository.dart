import 'chat_access_token.dart';

abstract class AuthTokenRepository {
  Future<ChatAccessToken> getAccessToken();
}
