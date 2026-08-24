import 'dart:io';
import 'package:chat_ui/core/utils/image_dimension_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageDimensionUtils Tests', () {
    test('returns 0x0 for non-existent file', () async {
      final file = File('/tmp/non_existent_image_test_file.png');
      final dimensions = await ImageDimensionUtils.getDimensions(file);
      expect(dimensions.width, 0);
      expect(dimensions.height, 0);
    });

    test('parses PNG header dimensions correctly', () async {
      final tempDir = Directory.systemTemp.createTempSync();
      final pngFile = File('${tempDir.path}/test.png');
      final pngBytes = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D,
        0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x01, 0x00, // width 256
        0x00, 0x00, 0x02, 0x00, // height 512
        0x08, 0x06, 0x00, 0x00, 0x00
      ];
      await pngFile.writeAsBytes(pngBytes);

      final dimensions = await ImageDimensionUtils.getDimensions(pngFile);
      expect(dimensions.width, 256);
      expect(dimensions.height, 512);

      tempDir.deleteSync(recursive: true);
    });
  });
}
