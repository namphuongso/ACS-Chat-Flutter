import '../entities/chat_access_token.dart';

abstract class AuthTokenRepository {
  Future<ChatAccessToken> getAccessToken(String roomId);
  ChatAccessToken? getCachedToken(String roomId);
  Future<void> refresh(String roomId);
  Future<void> clear(String roomId);
  Future<void> dispose();
  void cacheToken(String roomId, ChatAccessToken token);
}
