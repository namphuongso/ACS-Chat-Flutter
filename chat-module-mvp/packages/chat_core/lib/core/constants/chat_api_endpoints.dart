/// Tập trung toàn bộ API path của module chat. Không hard-code URL ở datasource.
abstract final class ChatApiEndpoints {
  // Auth token (BE)
  static String joinRoom(String roomId) => '/api/chat/join-room/$roomId';

  // Conversation (BE)
  static const getContacts = '/api/chat/get-contacts';
  static const getRoomChats = '/api/chat/get-room-chats';
  static const createRoom = '/api/chat/create-room';

  /// Ghim/bỏ ghim room — dùng query `roomId` + `pin`.
  static const pinRoom = '/api/chat/pin-room';

  // Group & Member Management (BE)
  static String getMembers(String roomId) => '/api/chat/get-members/$roomId';
  static const updateRoomInfo = '/api/chat/update-room-info';
  static const addParticipants = '/api/chat/add-participants';
  static const removeParticipants = '/api/chat/remove-participants';
  static const transferOwnership = '/api/chat/transfer-ownership';
  static const setRoleAdmin = '/api/chat/set-role-admin';
  static String leaveRoom(String roomId) => '/api/chat/leave-room/$roomId';

  /// Đóng (khóa) room — giải tán nhóm, không cho gửi tin/tham gia thêm
  /// (API docs mục 23).
  static String closeRoom(String roomId) => '/api/chat/close-room/$roomId';
  static const uploadFiles = '/api/files/uploads';
  static const createUploadSession = '/api/files/create-upload-session';
  static const completeUpload = '/api/files/complete-upload';

  // Message
  static const sendMessage = '/api/chat/send-message';
  static const getMessages = '/api/chat/get-messages';
  static const updateMessage = '/api/chat/update-message';
  static const deleteMessage = '/api/chat/delete-message';
  static const reactionMessage = '/api/chat/reaction-message';
  static const getMessageReactions = '/api/chat/get-message-reactions';
  static String getRoomReactions(String roomId) =>
      '/api/chat/get-room-reactions/$roomId';
  static const getReactionConfigs = '/api/chatadmin/get-reaction-configs';

  /// Ghim/bỏ ghim tin nhắn — dùng query `messageId` + `pin`.
  static const pinMessage = '/api/chat/pin-message';

  /// Danh sách tin đang ghim trong room — path param `roomId`.
  static String getPinnedMessages(String roomId) =>
      '/api/chat/get-pinned-messages/$roomId';

  static const getReader = '/api/chat/get-reader';
  static const getMessageResources = '/api/chat/get-message-resources';

  /// ACS Chat REST — dùng chung với [ChatAccessToken.endpoint] làm base.
  static String acsThreadMessages(String threadId) =>
      '/chat/threads/$threadId/messages';
}
