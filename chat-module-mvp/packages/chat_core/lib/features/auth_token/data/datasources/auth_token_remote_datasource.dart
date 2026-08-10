import '../models/chat_access_token_model.dart';

/// Nguồn dữ liệu ACS token từ BE (`POST /chat/generate-acs-token`).
abstract class AuthTokenRemoteDataSource {
  Future<ChatAccessTokenModel> fetchToken(String roomId);

  void dispose();
}
