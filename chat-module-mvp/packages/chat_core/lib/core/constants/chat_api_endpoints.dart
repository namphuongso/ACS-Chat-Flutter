/// Tập trung toàn bộ API path của module chat. Không hard-code URL ở datasource.
abstract final class ChatApiEndpoints {
  // Auth token (BE)
  static String joinRoom(String roomId) => '/api/chat/join-room/$roomId';

  // Conversation (BE)
  static const getContacts = '/api/chat/get-contacts';
  static const getRoomChats = '/api/chat/get-room-chats';
  static const createRoom = '/api/chat/create-room';
  static String markConversationRead(String id) =>
      '/api/chat/conversations/$id/read';

  /// Ghim/bỏ ghim room — dùng query `roomId` + `pin`.
  static const pinRoom = '/api/chat/pin-room';

  // Message
  static const sendMessage = '/api/chat/send-message';

  /// Ghim/bỏ ghim tin nhắn — dùng query `messageId` + `pin`.
  static const pinMessage = '/api/chat/pin-message';

  /// Danh sách tin đang ghim trong room — path param `roomId`.
  static String getPinnedMessages(String roomId) =>
      '/api/chat/get-pinned-messages/$roomId';

  /// ACS Chat REST — dùng chung với [ChatAccessToken.endpoint] làm base.
  static String acsThreadMessages(String threadId) =>
      '/chat/threads/$threadId/messages';
}
