import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import 'add_participants_screen.dart';

/// Trang danh sách thành viên của phòng nhóm, mở từ dòng "Thành viên"
/// trong [RoomSettingsScreen]. Admin có thể thêm/xóa thành viên và
/// chuyển quyền trưởng nhóm ngay tại đây.
class RoomMembersScreen extends ConsumerStatefulWidget {
  const RoomMembersScreen({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.isAdmin,
    required this.initialMembers,
    this.onMembersChanged,
  });

  final String roomId;
  final String currentUserId;
  final bool isAdmin;
  final List<ChatMember> initialMembers;

  /// Báo về màn hình Tùy chọn sau khi danh sách thành viên thay đổi
  /// (load lại từ BE, thêm/xóa/chuyển quyền) để đồng bộ UI.
  final ValueChanged<List<ChatMember>>? onMembersChanged;

  @override
  ConsumerState<RoomMembersScreen> createState() => _RoomMembersScreenState();
}

class _RoomMembersScreenState extends ConsumerState<RoomMembersScreen> {
  late List<ChatMember> _members;
  late bool _isAdmin;
  late bool _isOwner;

  @override
  void initState() {
    super.initState();
    _members = List.of(widget.initialMembers);
    final me = _members
        .where((member) => member.id == widget.currentUserId)
        .firstOrNull;
    _isOwner = me?.isOwner ?? false;
    _isAdmin = widget.isAdmin || _isOwner;
    _refreshMembers();
  }

  Future<void> _refreshMembers() async {
    try {
      final remoteMembers =
          await ref.read(getMembersUseCaseProvider)(widget.roomId);
      if (!mounted || remoteMembers.isEmpty) return;
      _applyMembers(remoteMembers);
    } catch (_) {
      // get-members lỗi thì giữ danh sách hiện có (từ join-room).
    }
  }

  void _applyMembers(List<ChatMember> members) {
    final me = members
        .where((member) => member.id == widget.currentUserId)
        .firstOrNull;
    setState(() {
      _members = members;
      _isOwner = me?.isOwner ?? false;
      _isAdmin = (me?.isAdmin ?? false) || _isOwner;
    });
    widget.onMembersChanged?.call(members);
  }

  @override
  Widget build(BuildContext context) {
    final uiConfig = ref.watch(chatUiConfigProvider);
    final primary =
        uiConfig.primaryActionColor ?? Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: uiConfig.roomBackgroundColor ?? const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(
          'Thành viên (${_members.length})',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: uiConfig.appBarIconColor ?? Colors.white,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        scrolledUnderElevation: 0,
        backgroundColor:
            uiConfig.appBarBackgroundColor ?? const Color(0xFF0787E8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme:
            IconThemeData(color: uiConfig.appBarIconColor ?? Colors.white),
        foregroundColor: uiConfig.appBarIconColor ?? Colors.white,
      ),
      body: Column(
        children: [
          Material(
            color: uiConfig.surfaceColor ?? Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Thành viên',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: uiConfig.secondaryTextColor ?? Colors.black87,
                    ),
                  ),
                  if (_isAdmin)
                    TextButton.icon(
                      onPressed: _showAddParticipantsDialog,
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Thêm thành viên'),
                      style: TextButton.styleFrom(foregroundColor: primary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _members.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa tải được danh sách thành viên',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : Material(
                    color: uiConfig.surfaceColor ?? Colors.white,
                    child: ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final isMe = member.id == widget.currentUserId;
                        final hasAvatar = isNetworkAvatar(member.avatarUrl);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFF0F2F5),
                            backgroundImage: hasAvatar
                                ? NetworkImage(member.avatarUrl!)
                                : null,
                            child: !hasAvatar
                                ? Text(
                                    member.displayName.isNotEmpty
                                        ? member.displayName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  )
                                : null,
                          ),
                          title:
                              Text(member.displayName + (isMe ? ' (Bạn)' : '')),
                          subtitle: member.isOwner
                              ? const Text(
                                  'Owner',
                                  style: TextStyle(
                                    color: Color(0xFFD97706),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : member.isAdmin
                                  ? Text(
                                      'Admin',
                                      style: TextStyle(
                                        color: primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    )
                                  : null,
                          trailing: !isMe &&
                                  (_isOwner ||
                                      (_isAdmin &&
                                          !member.isOwner &&
                                          !member.isAdmin))
                              ? PopupMenuButton<String>(
                                  color: Colors.white,
                                  surfaceTintColor: Colors.transparent,
                                  elevation: 6,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  onSelected: (value) =>
                                      _handleMemberAction(value, member),
                                  itemBuilder: (context) {
                                    final items = <PopupMenuEntry<String>>[];
                                    if (_isOwner) {
                                      items.add(const PopupMenuItem(
                                        value: 'transfer',
                                        child: ChatActionMenuTile(
                                          icon:
                                              Icons.workspace_premium_outlined,
                                          label: 'Chuyển quyền Owner',
                                        ),
                                      ));
                                      if (member.isAdmin) {
                                        items.add(const PopupMenuItem(
                                          value: 'remove_admin',
                                          child: ChatActionMenuTile(
                                            icon:
                                                Icons.remove_moderator_outlined,
                                            label: 'Gỡ quyền Admin',
                                          ),
                                        ));
                                      } else {
                                        items.add(const PopupMenuItem(
                                          value: 'make_admin',
                                          child: ChatActionMenuTile(
                                            icon: Icons.add_moderator_outlined,
                                            label: 'Cấp quyền Admin',
                                          ),
                                        ));
                                      }
                                    }
                                    items.add(PopupMenuItem(
                                      value: 'remove',
                                      child: ChatActionMenuTile(
                                        icon: Icons.person_remove_outlined,
                                        label: 'Xóa khỏi nhóm',
                                        color:
                                            uiConfig.dangerColor ?? Colors.red,
                                      ),
                                    ));
                                    return items;
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _handleMemberAction(String action, ChatMember member) {
    if (action == 'transfer') {
      _showTransferOwnershipConfirmDialog(member);
    } else if (action == 'make_admin') {
      _setRoleAdmin(member, true);
    } else if (action == 'remove_admin') {
      _setRoleAdmin(member, false);
    } else if (action == 'remove') {
      _showRemoveMemberConfirmDialog(member);
    }
  }

  Future<void> _showAddParticipantsDialog() async {
    final selectedUserIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddParticipantsScreen(
          currentMembers: _members,
        ),
      ),
    );
    if (selectedUserIds != null && selectedUserIds.isNotEmpty && mounted) {
      _addMembers(selectedUserIds);
    }
  }

  Future<void> _addMembers(List<String> userIds) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final addedCount = await ref.read(addParticipantsUseCaseProvider)(
        roomId: widget.roomId,
        participantIds: userIds,
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (addedCount > 0) {
        await _refreshMembers();
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã thêm thành viên vào nhóm',
            config: ref.read(chatUiConfigProvider),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể thêm thành viên')),
        );
      }
    } catch (e, st) {
      ChatLogger.error('Add participants error', error: e, stackTrace: st);
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading
      showChatToast(
        context,
        message: 'Thao tác không thành công',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Future<void> _showTransferOwnershipConfirmDialog(ChatMember member) async {
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Chuyển quyền Owner',
      message:
          'Bạn có chắc chắn muốn chuyển quyền Owner cho ${member.displayName}? Sau khi chuyển, ${member.displayName} sẽ trở thành Owner mới.',
    );
    if (confirmed && mounted) _transferOwnership(member.id);
  }

  Future<void> _transferOwnership(String toUserId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await ref.read(transferOwnershipUseCaseProvider)(
        roomId: widget.roomId,
        toUserId: toUserId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (success) {
        await _refreshMembers();
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã chuyển quyền Owner thành công',
            config: ref.read(chatUiConfigProvider),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể chuyển quyền Owner')),
        );
      }
    } catch (e, st) {
      ChatLogger.error('Transfer ownership error', error: e, stackTrace: st);
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading
      showChatToast(
        context,
        message: 'Không thể chuyển quyền Owner',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Future<void> _setRoleAdmin(ChatMember member, bool admin) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await ref.read(setRoleAdminUseCaseProvider)(
        roomId: widget.roomId,
        userId: member.id,
        admin: admin,
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (success) {
        await _refreshMembers();
        if (mounted) {
          showChatToast(
            context,
            message: admin
                ? 'Đã phong ${member.displayName} làm Admin'
                : 'Đã gỡ quyền Admin của ${member.displayName}',
            config: ref.read(chatUiConfigProvider),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cập nhật quyền Admin')),
        );
      }
    } catch (e, st) {
      ChatLogger.error('Set role admin error', error: e, stackTrace: st);
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading
      showChatToast(
        context,
        message: 'Không thể cập nhật quyền Admin',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Future<void> _showRemoveMemberConfirmDialog(ChatMember member) async {
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Xóa khỏi nhóm',
      message:
          'Bạn có chắc chắn muốn xóa ${member.displayName} khỏi phòng chat này không?',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (confirmed && mounted) _removeMember(member.id);
  }

  Future<void> _removeMember(String userId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final removedCount = await ref.read(removeParticipantsUseCaseProvider)(
        roomId: widget.roomId,
        participantIds: [userId],
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (removedCount > 0) {
        await _refreshMembers();
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã xóa thành viên khỏi nhóm',
            config: ref.read(chatUiConfigProvider),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể xóa thành viên')),
        );
      }
    } catch (e, st) {
      ChatLogger.error('Remove member error', error: e, stackTrace: st);
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading
      showChatToast(
        context,
        message: 'Không thể xóa thành viên',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }
}
