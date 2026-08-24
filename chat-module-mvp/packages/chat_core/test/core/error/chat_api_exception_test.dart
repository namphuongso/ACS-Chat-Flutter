import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  group('ChatException Hierarchy Tests', () {
    test('ChatApiException stores status code and returns isHttpError = true', () {
      final exc = ChatApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Resource missing',
      );
      expect(exc.isHttpError, isTrue);
      expect(exc.isNotFound, isTrue);
      expect(exc.isUnauthorized, isFalse);
      expect(exc.toString(), contains('ChatApiException(404 NOT_FOUND)'));
    });

    test('ChatDataException returns isHttpError = false', () {
      final exc = ChatDataException(
        code: 'DATA_NULL',
        message: 'Response payload is null',
      );
      expect(exc.isHttpError, isFalse);
      expect(exc.code, 'DATA_NULL');
      expect(exc.toString(), contains('ChatDataException(DATA_NULL)'));
      expect(exc, isA<ChatException>());
    });
  });
}
