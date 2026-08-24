import 'dart:async';
import 'dart:collection';
import '../../domain/entities/message.dart';
import '../models/message_model.dart';

/// Manages stream controllers and deduplication for incoming WebSocket messages.
class WebSocketEventDispatcher {
  final Map<String, StreamController<MessageModel>> _threadControllers = {};
  final Queue<String> _recentMessageIdQueue = Queue<String>();
  final Set<String> _recentMessageIdSet = <String>{};
  static const int _maxRecentMessages = 100;
  StreamController<MessageModel>? _listController;

  Map<String, StreamController<MessageModel>> get threadControllers => _threadControllers;

  Stream<MessageModel> watchNewMessages(String threadId) {
    final existing = _threadControllers[threadId];
    if (existing != null) return existing.stream;

    final controller = StreamController<MessageModel>.broadcast();
    _threadControllers[threadId] = controller;
    return controller.stream;
  }

  Stream<MessageModel> watchListMessages() {
    final existing = _listController;
    if (existing != null) return existing.stream;
    _listController = StreamController<MessageModel>.broadcast();
    return _listController!.stream;
  }

  void emit(MessageModel message) {
    // Only deduplicate actual text/media/system messages by ID.
    // Reaction and pin updates belong to target messages and must always be dispatched.
    final isControlOrSignalMessage =
        message.type == MessageType.reactionUpdate ||
        message.type == MessageType.messagePinUpdate ||
        message.type == MessageType.roomPinnedUpdate ||
        message.type == MessageType.roomUnpinnedUpdate;

    if (!isControlOrSignalMessage && message.id.isNotEmpty) {
      if (_recentMessageIdSet.contains(message.id)) {
        return; // Ignore duplicate message
      }
      _recentMessageIdSet.add(message.id);
      _recentMessageIdQueue.addLast(message.id);
      if (_recentMessageIdQueue.length > _maxRecentMessages) {
        final evicted = _recentMessageIdQueue.removeFirst();
        _recentMessageIdSet.remove(evicted);
      }
    }

    final threadController = _threadControllers[message.threadId];
    if (threadController != null && !threadController.isClosed) {
      threadController.add(message);
    }
    final listController = _listController;
    if (listController != null && !listController.isClosed) {
      listController.add(message);
    }
  }

  Future<void> stopWatching(String threadId) async {
    final controller = _threadControllers.remove(threadId);
    await controller?.close();
  }

  Future<void> stopWatchingList() async {
    final controller = _listController;
    _listController = null;
    await controller?.close();
  }

  Future<void> dispose() async {
    for (final controller in _threadControllers.values) {
      await controller.close();
    }
    _threadControllers.clear();
    await _listController?.close();
    _listController = null;
    _recentMessageIdQueue.clear();
    _recentMessageIdSet.clear();
  }
}
