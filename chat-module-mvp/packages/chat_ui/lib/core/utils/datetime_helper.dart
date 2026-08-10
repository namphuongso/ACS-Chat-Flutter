class DateTimeHelper {
  /// Format thời gian tin nhắn cuối dạng tương đối (Vừa xong, n phút trước, n giờ trước,...)
  static String formatRelative(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else {
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      if (dateTime.year == now.year) {
        return '$day/$month';
      }
      final year = dateTime.year;
      return '$day/$month/$year';
    }
  }
}
