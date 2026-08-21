import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/presentation/providers/shared_providers.dart';
export '../../../shared/presentation/providers/shared_providers.dart';
import '../notifiers/thread_messages_notifier.dart';

// Thread Use Cases
final sendMessageUseCaseProvider = Provider<SendMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return SendMessageUseCase(repo);
});

final updateMessageUseCaseProvider = Provider<UpdateMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return UpdateMessageUseCase(repo);
});

final deleteMessageUseCaseProvider = Provider<DeleteMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return DeleteMessageUseCase(repo);
});

final listMessagesUseCaseProvider = Provider<ListMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return ListMessagesUseCase(repo);
});

final watchNewMessagesUseCaseProvider =
    Provider<WatchNewMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return WatchNewMessagesUseCase(repo);
});

final stopWatchingMessagesUseCaseProvider =
    Provider<StopWatchingMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return StopWatchingMessagesUseCase(repo);
});

final pinMessageUseCaseProvider = Provider<PinMessageUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return PinMessageUseCase(repo);
});

final getPinnedMessagesUseCaseProvider =
    Provider<GetPinnedMessagesUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return GetPinnedMessagesUseCase(repo);
});

final getMessageReadersUseCaseProvider =
    Provider<GetMessageReadersUseCase>((ref) {
  final repo = ref.watch(messageRepositoryProvider);
  return GetMessageReadersUseCase(repo);
});

class MessageReadersQuery {
  const MessageReadersQuery({
    required this.roomId,
    required this.messageId,
    this.read,
  });

  final String roomId;
  final String messageId;
  final bool? read;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageReadersQuery &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          messageId == other.messageId &&
          read == other.read;

  @override
  int get hashCode => roomId.hashCode ^ messageId.hashCode ^ read.hashCode;
}

final messageReadersProvider = FutureProvider.autoDispose
    .family<List<MessageReader>, MessageReadersQuery>((ref, query) {
  final useCase = ref.watch(getMessageReadersUseCaseProvider);
  return useCase(
    roomId: query.roomId,
    messageId: query.messageId,
    read: query.read,
  );
});

final roomIdProvider = Provider<String>((ref) => throw UnimplementedError());
final threadIdProvider = Provider<String>((ref) => throw UnimplementedError());

final threadMessagesProvider =
    NotifierProvider.autoDispose<ThreadMessagesNotifier, List<Message>>(
  ThreadMessagesNotifier.new,
  dependencies: [
    roomIdProvider,
    threadIdProvider,
    listMessagesUseCaseProvider,
    watchNewMessagesUseCaseProvider,
    sendMessageUseCaseProvider,
    updateMessageUseCaseProvider,
    deleteMessageUseCaseProvider,
    pinMessageUseCaseProvider,
    stopWatchingMessagesUseCaseProvider,
    getPinnedMessagesUseCaseProvider,
  ],
);

final uploadFileViaSasUseCaseProvider = Provider<UploadFileViaSasUseCase>((ref) {
  final repo = ref.watch(conversationRepositoryProvider);
  return UploadFileViaSasUseCase(repo);
});

class MediaUploadItemProgress {
  final String fileName;
  final String path;
  final double progress;

  const MediaUploadItemProgress({
    required this.fileName,
    required this.path,
    required this.progress,
  });

  MediaUploadItemProgress copyWith({double? progress}) {
    return MediaUploadItemProgress(
      fileName: fileName,
      path: path,
      progress: progress ?? this.progress,
    );
  }
}

class MediaUploadProgressNotifier
    extends Notifier<Map<String, List<MediaUploadItemProgress>?>> {
  @override
  Map<String, List<MediaUploadItemProgress>?> build() => const {};

  void setRoomProgress(String roomId, List<MediaUploadItemProgress>? items) {
    state = {
      ...state,
      roomId: items,
    };
  }

  void setItemProgress(String roomId, String fileName, double progress) {
    final current = state[roomId];
    if (current == null) return;

    final updated = current.map((item) {
      if (item.fileName == fileName) {
        return item.copyWith(progress: progress);
      }
      return item;
    }).toList();

    state = {
      ...state,
      roomId: updated,
    };
  }
}

final mediaUploadProgressProvider = NotifierProvider<
    MediaUploadProgressNotifier,
    Map<String, List<MediaUploadItemProgress>?>>(
  MediaUploadProgressNotifier.new,
);

/// Lỗi upload media theo từng room — ThreadScreen listen để hiển thị toast,
/// giúp người dùng biết khi có tệp không gửi được (thay vì im lặng bỏ qua).
class MediaUploadErrorNotifier extends Notifier<Map<String, String?>> {
  @override
  Map<String, String?> build() => const {};

  void setError(String roomId, String? message) {
    state = {...state, roomId: message};
  }

  void clear(String roomId) {
    if (state[roomId] == null) return;
    state = {...state, roomId: null};
  }
}

final mediaUploadErrorProvider =
    NotifierProvider<MediaUploadErrorNotifier, Map<String, String?>>(
  MediaUploadErrorNotifier.new,
);

final getMessageResourcesUseCaseProvider =
    Provider<GetMessageResourcesUseCase>((ref) {
  return GetMessageResourcesUseCase(ref.watch(messageRepositoryProvider));
});

enum RoomResourceCategory {
  media,
  file,
  link,
}

class RoomResourceQuery {
  const RoomResourceQuery({
    required this.roomId,
    required this.category,
    this.pageIndex = 1,
    this.pageSize = 50,
    this.keyword,
  });

  final String roomId;
  final RoomResourceCategory category;
  final int pageIndex;
  final int pageSize;
  final String? keyword;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoomResourceQuery &&
          runtimeType == other.runtimeType &&
          roomId == other.roomId &&
          category == other.category &&
          pageIndex == other.pageIndex &&
          pageSize == other.pageSize &&
          keyword == other.keyword;

  @override
  int get hashCode =>
      roomId.hashCode ^
      category.hashCode ^
      pageIndex.hashCode ^
      pageSize.hashCode ^
      keyword.hashCode;
}

class RoomResourceGroupResult {
  const RoomResourceGroupResult({
    required this.items,
    required this.totalCount,
  });

  final List<MessageResource> items;
  final int totalCount;
}

final roomResourcePreviewProvider = FutureProvider.autoDispose.family<
    RoomResourceGroupResult,
    ({String roomId, RoomResourceCategory category})>((ref, args) async {
  final useCase = ref.watch(getMessageResourcesUseCaseProvider);

  if (args.category == RoomResourceCategory.media) {
    final imageResult = await useCase(
      roomId: args.roomId,
      resourceType: MessageResourceType.image,
      pageIndex: 1,
      pageSize: 3,
    );
    final videoResult = await useCase(
      roomId: args.roomId,
      resourceType: MessageResourceType.video,
      pageIndex: 1,
      pageSize: 3,
    );
    final combined = <MessageResource>[...imageResult.items, ...videoResult.items]
      ..sort((a, b) => b.createdDate.compareTo(a.createdDate));
    final previewItems = combined.take(3).toList();
    final total = imageResult.items.length + videoResult.items.length;
    return RoomResourceGroupResult(
      items: previewItems,
      totalCount: total,
    );
  } else if (args.category == RoomResourceCategory.file) {
    final fileResult = await useCase(
      roomId: args.roomId,
      resourceType: MessageResourceType.file,
      pageIndex: 1,
      pageSize: 3,
    );
    return RoomResourceGroupResult(
      items: fileResult.items.take(3).toList(),
      totalCount: fileResult.items.length,
    );
  } else {
    final linkResult = await useCase(
      roomId: args.roomId,
      resourceType: MessageResourceType.link,
      pageIndex: 1,
      pageSize: 3,
    );
    return RoomResourceGroupResult(
      items: linkResult.items.take(3).toList(),
      totalCount: linkResult.items.length,
    );
  }
});
