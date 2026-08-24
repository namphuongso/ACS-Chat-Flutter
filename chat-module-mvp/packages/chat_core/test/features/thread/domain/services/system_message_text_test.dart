import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('SystemMessageTextBuilder Tests', () {
    tearDown(() {
      SystemMessageTextBuilder.setCustomResolver(null);
    });

    test('builds memberjoined system text correctly', () {
      final text = SystemMessageTextBuilder.build(
        eventType: 'memberjoined',
        actorFallback: 'Alice',
        joinedUserFallbacks: ['Bob'],
      );
      expect(text, contains('**Alice** đã thêm **Bob** vào nhóm'));
    });

    test('uses customResolver when provided', () {
      SystemMessageTextBuilder.setCustomResolver((
        {required eventType,
        actorFallback = '',
        isSelfRemoved = false,
        joinedUserFallbacks = const [],
        json = const {},
        payload = const {},
        targetFallback = ''}) {
        return 'Custom text for $eventType';
      });

      final text = SystemMessageTextBuilder.build(eventType: 'memberjoined');
      expect(text, 'Custom text for memberjoined');
    });
  });
}
