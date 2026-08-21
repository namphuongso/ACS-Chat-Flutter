import 'package:chat_core/chat_core.dart';
import 'package:flutter/foundation.dart';

@immutable
class ThreadState {
  const ThreadState({
    this.messages = const [],
    this.pinnedMessages = const [],
    this.reactionsMap = const {},
    this.historyLoaded = false,
    this.myAcsUserId = '',
    this.hasMore = true,
    this.isLoadingOlder = false,
    this.cursor,
  });

  final List<Message> messages;
  final List<PinnedMessage> pinnedMessages;
  final Map<String, MessageReactionSummary> reactionsMap;
  final bool historyLoaded;
  final String myAcsUserId;
  final bool hasMore;
  final bool isLoadingOlder;
  final String? cursor;

  ThreadState copyWith({
    List<Message>? messages,
    List<PinnedMessage>? pinnedMessages,
    Map<String, MessageReactionSummary>? reactionsMap,
    bool? historyLoaded,
    String? myAcsUserId,
    bool? hasMore,
    bool? isLoadingOlder,
    String? cursor,
  }) {
    return ThreadState(
      messages: messages ?? this.messages,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
      reactionsMap: reactionsMap ?? this.reactionsMap,
      historyLoaded: historyLoaded ?? this.historyLoaded,
      myAcsUserId: myAcsUserId ?? this.myAcsUserId,
      hasMore: hasMore ?? this.hasMore,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      cursor: cursor ?? this.cursor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadState &&
          runtimeType == other.runtimeType &&
          listEquals(messages, other.messages) &&
          listEquals(pinnedMessages, other.pinnedMessages) &&
          mapEquals(reactionsMap, other.reactionsMap) &&
          historyLoaded == other.historyLoaded &&
          myAcsUserId == other.myAcsUserId &&
          hasMore == other.hasMore &&
          isLoadingOlder == other.isLoadingOlder &&
          cursor == other.cursor;

  @override
  int get hashCode =>
      Object.hash(
        Object.hashAll(messages),
        Object.hashAll(pinnedMessages),
        historyLoaded,
        myAcsUserId,
        hasMore,
        isLoadingOlder,
        cursor,
      );
}
