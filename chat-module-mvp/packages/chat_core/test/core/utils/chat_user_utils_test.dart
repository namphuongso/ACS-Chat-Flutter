import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChatUserUtils Tests', () {
    test('normalizeUserId strips 8:acs: prefix and handles GUID format', () {
      expect(ChatUserUtils.normalizeUserId('8:acs:abc_12345'), '12345');
      expect(ChatUserUtils.normalizeUserId('12345'), '12345');
      expect(ChatUserUtils.normalizeUserId(''), '');
    });

    test('isSameUser compares normalized user IDs correctly', () {
      expect(
        ChatUserUtils.isSameUser('8:acs:prefix_user123', 'USER123'),
        isTrue,
      );
      expect(
        ChatUserUtils.isSameUser('user123', 'user456'),
        isFalse,
      );
    });
  });
}
