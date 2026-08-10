import '../entities/chat_access_token.dart';
import '../repositories/auth_token_repository.dart';

class GetAccessTokenUseCase {
  GetAccessTokenUseCase(this._repository);
  final AuthTokenRepository _repository;

  Future<ChatAccessToken> call(String roomId) =>
      _repository.getAccessToken(roomId);
}
