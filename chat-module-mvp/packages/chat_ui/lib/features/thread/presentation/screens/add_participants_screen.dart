import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../contact/presentation/notifiers/contact_list_notifier.dart';

class AddParticipantsScreen extends ConsumerStatefulWidget {
  const AddParticipantsScreen({
    super.key,
    required this.currentMembers,
    this.title = 'Thêm bạn vào nhóm',
    this.onAdd,
  });

  final List<ChatMember> currentMembers;
  final String title;
  final ValueChanged<List<String>>? onAdd;

  @override
  ConsumerState<AddParticipantsScreen> createState() =>
      _AddParticipantsScreenState();
}

class _AddParticipantsScreenState extends ConsumerState<AddParticipantsScreen> {
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 160) {
      ref.read(contactListNotifierProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _submit() {
    final list = _selectedIds.toList();
    if (widget.onAdd != null) {
      widget.onAdd!(list);
    }
    Navigator.pop(context, list);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(contactListNotifierProvider);
    final notifier = ref.read(contactListNotifierProvider.notifier);
    final uiConfig = ref.watch(chatUiConfigProvider);
    final primary =
        uiConfig.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    final surface = uiConfig.surfaceColor ?? Colors.white;

    final filteredContacts = state.contacts.where((c) {
      final alreadyMember = widget.currentMembers.any((m) => m.id == c.id);
      return !alreadyMember;
    }).toList();

    final selectedUsers =
        state.contacts.where((c) => _selectedIds.contains(c.id)).toList();

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              'Đã chọn: ${_selectedIds.length}',
              style: TextStyle(
                fontSize: 12,
                color: uiConfig.secondaryTextColor ?? Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm tên hoặc số điện thoại',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                prefixIcon:
                    Icon(Icons.search, color: Colors.grey.shade600, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.cancel,
                            color: Colors.grey.shade500, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          notifier.search('');
                        },
                      )
                    : null,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 14),
                fillColor:
                    uiConfig.formFieldFillColor ?? const Color(0xFFF2F3F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: primary, width: 1.5),
                ),
              ),
              onChanged: (val) {
                setState(() {});
                notifier.search(val);
              },
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredContacts.isEmpty
                    ? Center(
                        child: Text(
                          'Không tìm thấy danh bạ hợp lệ',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    : ListView.separated(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: filteredContacts.length +
                            (state.isLoadingMore ? 1 : 0),
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 68,
                          color: Colors.grey.shade200,
                        ),
                        itemBuilder: (context, index) {
                          if (index == filteredContacts.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          final user = filteredContacts[index];
                          final isSelected = _selectedIds.contains(user.id);
                          final hasAvatar = isNetworkAvatar(user.avatarUrl);

                          return Material(
                            color: isSelected
                                ? primary.withValues(alpha: 0.05)
                                : Colors.transparent,
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 2),
                              leading: Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: const Color(0xFFF0F2F5),
                                    backgroundImage: hasAvatar
                                        ? NetworkImage(user.avatarUrl!)
                                        : null,
                                    child: !hasAvatar
                                        ? Text(
                                            user.displayName.isNotEmpty
                                                ? user.displayName[0]
                                                    .toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Colors.black87,
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                              title: Text(
                                user.displayName,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                              subtitle: user.email?.isNotEmpty == true
                                  ? Text(
                                      user.email!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    )
                                  : null,
                              trailing: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      isSelected ? primary : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? primary
                                        : Colors.grey.shade400,
                                    width: 1.8,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(user.id);
                                  } else {
                                    _selectedIds.add(user.id);
                                  }
                                });
                              },
                            ),
                          );
                        },
                      ),
          ),
          if (_selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: selectedUsers.length,
                        itemBuilder: (context, index) {
                          final u = selectedUsers[index];
                          final hasAv = isNetworkAvatar(u.avatarUrl);
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              children: [
                                CircleAvatar(
                                  radius: 22,
                                  backgroundColor: const Color(0xFFF0F2F5),
                                  backgroundImage:
                                      hasAv ? NetworkImage(u.avatarUrl!) : null,
                                  child: !hasAv
                                      ? Text(
                                          u.displayName.isNotEmpty
                                              ? u.displayName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedIds.remove(u.id);
                                      });
                                    },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade700,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: const Icon(
                                        Icons.close,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton(
                    onPressed: _submit,
                    elevation: 2,
                    backgroundColor: primary,
                    shape: const CircleBorder(),
                    child: const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
