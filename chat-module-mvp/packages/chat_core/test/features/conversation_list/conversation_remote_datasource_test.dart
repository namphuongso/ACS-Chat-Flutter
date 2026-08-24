import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('ConversationRemoteDataSource Exception Contracts Tests', () {
    test('ChatDataException throws correctly on null data', () {
      final exc = ChatDataException(
        code: 'CREATE_ROOM_NULL_DATA',
        message: 'Không thể tạo phòng chat.',
      );
      expect(exc.code, 'CREATE_ROOM_NULL_DATA');
      expect(exc.isHttpError, isFalse);
    });
  });
}
