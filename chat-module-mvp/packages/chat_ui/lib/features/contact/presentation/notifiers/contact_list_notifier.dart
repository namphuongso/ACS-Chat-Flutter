import 'package:chat_core/chat_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/contact_providers.dart';

class ContactListState {
  const ContactListState({
    this.contacts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.keyword = '',
    this.pageIndex = 0,
    this.error,
  });

  final List<ChatUser> contacts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String keyword;
  final int pageIndex;
  final String? error;

  ContactListState copyWith({
    List<ChatUser>? contacts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? keyword,
    int? pageIndex,
    String? error,
  }) {
    return ContactListState(
      contacts: contacts ?? this.contacts,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      keyword: keyword ?? this.keyword,
      pageIndex: pageIndex ?? this.pageIndex,
      error: error,
    );
  }
}

class ContactListNotifier extends Notifier<ContactListState> {
  late final SearchContactsUseCase _searchContactsUseCase;

  @override
  ContactListState build() {
    _searchContactsUseCase = ref.watch(searchContactsUseCaseProvider);
    Future.microtask(() => loadContacts());
    return const ContactListState();
  }

  Future<void> loadContacts() async {
    if (state.isLoading) return;

    state = state.copyWith(
        isLoading: true, error: null, pageIndex: 1, hasMore: true);

    try {
      final result = await _searchContactsUseCase(
        keyword: state.keyword,
        pageIndex: 1,
      );

      if (!ref.mounted) return;
      state = state.copyWith(
        contacts: result.items,
        isLoading: false,
        hasMore: result.hasMore,
        pageIndex: 2,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true, error: null);

    try {
      final result = await _searchContactsUseCase(
        keyword: state.keyword,
        pageIndex: state.pageIndex,
      );

      if (!ref.mounted) return;

      final existingIds = state.contacts.map((c) => c.id).toSet();
      final newItems =
          result.items.where((c) => !existingIds.contains(c.id)).toList();

      if (newItems.isEmpty) {
        state = state.copyWith(
          isLoadingMore: false,
          hasMore: false,
        );
      } else {
        state = state.copyWith(
          contacts: [...state.contacts, ...newItems],
          isLoadingMore: false,
          hasMore: result.hasMore,
          pageIndex: state.pageIndex + 1,
        );
      }
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  void search(String keyword) {
    state = state.copyWith(keyword: keyword);
    loadContacts();
  }
}

final contactListNotifierProvider =
    NotifierProvider<ContactListNotifier, ContactListState>(
        ContactListNotifier.new);
