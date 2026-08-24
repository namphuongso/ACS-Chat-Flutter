import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show instantiateImageCodec;
import 'package:chat_core/chat_core.dart';

class ImageDimensions {
  const ImageDimensions(this.width, this.height);
  final int width;
  final int height;
}

class ImageDimensionUtils {
  static Future<ImageDimensions> getDimensions(File file) async {
    if (!await file.exists()) {
      return const ImageDimensions(0, 0);
    }

    try {
      final headerBytes = await _readHeaderBytes(file, 2048);
      if (headerBytes.isNotEmpty) {
        final parsed = _parseHeaderDimensions(headerBytes);
        if (parsed != null && parsed.width > 0 && parsed.height > 0) {
          return parsed;
        }
      }
    } catch (e) {
      ChatLogger.warn('Header image dimension parse failed: $e');
    }

    try {
      final bytes = await file.readAsBytes();
      final codec = await instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return ImageDimensions(frame.image.width, frame.image.height);
    } catch (e) {
      ChatLogger.warn('Fallback instantiateImageCodec failed: $e');
      return const ImageDimensions(0, 0);
    }
  }

  static Future<Uint8List> _readHeaderBytes(File file, int maxBytes) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      final length = await raf.length();
      final bytesToRead = length < maxBytes ? length : maxBytes;
      return await raf.read(bytesToRead);
    } finally {
      await raf.close();
    }
  }

  static ImageDimensions? _parseHeaderDimensions(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      final data = ByteData.sublistView(bytes);
      final width = data.getUint32(16, Endian.big);
      final height = data.getUint32(20, Endian.big);
      return ImageDimensions(width, height);
    }

    if (bytes.length >= 10 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      int offset = 2;
      while (offset < bytes.length - 8) {
        if (bytes[offset] != 0xFF) break;
        final marker = bytes[offset + 1];
        offset += 2;
        if (marker == 0xD8 || marker == 0xD9) continue;
        if (offset + 2 > bytes.length) break;
        final length = (bytes[offset] << 8) | bytes[offset + 1];
        if (length < 2) break;

        final isSof = (marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF);
        if (isSof && offset + 7 < bytes.length) {
          final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
          final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
          return ImageDimensions(width, height);
        }
        offset += length;
      }
    }

    if (bytes.length >= 10 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      final data = ByteData.sublistView(bytes);
      final width = data.getUint16(6, Endian.little);
      final height = data.getUint16(8, Endian.little);
      return ImageDimensions(width, height);
    }

    if (bytes.length >= 30 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x58 &&
          bytes.length >= 30) {
        final width =
            1 + (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16));
        final height =
            1 + (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16));
        return ImageDimensions(width, height);
      }
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x20 &&
          bytes.length >= 30) {
        final width = ((bytes[27] << 8) | bytes[26]) & 0x3FFF;
        final height = ((bytes[29] << 8) | bytes[28]) & 0x3FFF;
        return ImageDimensions(width, height);
      }
      if (bytes[12] == 0x56 &&
          bytes[13] == 0x50 &&
          bytes[14] == 0x38 &&
          bytes[15] == 0x4C &&
          bytes.length >= 25) {
        final b0 = bytes[21];
        final b1 = bytes[22];
        final b2 = bytes[23];
        final b3 = bytes[24];
        final width = 1 + (((b1 & 0x3F) << 8) | b0);
        final height = 1 + (((b3 & 0x0F) << 10) | (b2 << 2) | ((b1 & 0xC0) >> 6));
        return ImageDimensions(width, height);
      }
    }

    return null;
  }
}
