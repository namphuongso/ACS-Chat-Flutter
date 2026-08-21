/// Helper tra cứu MIME type dùng chung toàn bộ Chat Module.
///
/// Hỗ trợ chuẩn xác 14 định dạng mở rộng (whitelist BE):
/// - Images: jpg, jpeg, png, heic, heif
/// - Documents: pdf, doc, docx, xls, xlsx, ppt, pptx
/// - Videos: mp4, mov
class ChatMimeUtils {
  static const Map<String, String> _mimeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };

  /// Trả về MIME type từ tên file hoặc đường dẫn.
  /// Mặc định trả về `application/octet-stream` nếu extension không nằm trong bảng tra.
  static String lookupMimeType(String fileName, {String? defaultType}) {
    final clean = fileName.trim().toLowerCase();
    final dotIndex = clean.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == clean.length - 1) {
      return defaultType ?? 'application/octet-stream';
    }
    final ext = clean.substring(dotIndex + 1);
    return _mimeMap[ext] ?? defaultType ?? 'application/octet-stream';
  }
}
