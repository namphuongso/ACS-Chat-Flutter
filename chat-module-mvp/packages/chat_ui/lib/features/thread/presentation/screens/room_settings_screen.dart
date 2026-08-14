import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/chat_ui_config.dart';
import '../../../../core/utils/avatar_utils.dart';
import '../../../../core/widgets/chat_dialogs.dart';
import '../../../conversation_list/presentation/providers/conversation_providers.dart';
import '../../../shared/presentation/providers/shared_providers.dart';
import 'add_participants_screen.dart';

class RoomSettingsScreen extends ConsumerStatefulWidget {
  const RoomSettingsScreen({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.roomType,
    this.onRoomChanged,
    this.onSystemMessage,
  });

  final String roomId;
  final String currentUserId;
  final ConversationType roomType;
  final ValueChanged<Conversation>? onRoomChanged;
  final ValueChanged<String>? onSystemMessage;

  @override
  ConsumerState<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends ConsumerState<RoomSettingsScreen> {
  bool _isLoading = true;
  List<ChatMember> _members = [];
  bool _isAdmin = false;
  Conversation? _roomDetails;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final room =
          await ref.read(getConversationUseCaseProvider)(widget.roomId);

      // join-room đã trả sẵn `members`, gồm cả isAdmin. Dùng dữ liệu này
      // ngay để trang chi tiết không bị trống nếu endpoint get-members chưa
      // đồng bộ hoặc trả schema khác. Nếu get-members hoạt động thì ưu tiên
      // danh sách mới hơn từ endpoint đó.
      var members = _asMembers(room.participants);
      try {
        final remoteMembers =
            await ref.read(getMembersUseCaseProvider)(widget.roomId);
        if (remoteMembers.isNotEmpty) members = remoteMembers;
      } catch (_) {
        // Dữ liệu join-room vẫn đủ để hiển thị thành viên và quyền quản trị.
      }

      final myMember = members
          .where((member) => member.id == widget.currentUserId)
          .firstOrNull;

      if (myMember == null && members.isNotEmpty) {
        if (!mounted) return;
        showChatToast(
          context,
          message: 'Bạn đã bị xóa khỏi phòng chat này',
          isError: true,
          config: ref.read(chatUiConfigProvider),
        );
        ref.read(conversationListProvider.notifier).removeRoom(widget.roomId);
        Navigator.pop(context, true);
        return;
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _roomDetails = room;
        _isAdmin = myMember?.isAdmin ?? false;
        _isLoading = false;
      });
      widget.onRoomChanged?.call(room.copyWith(participants: members));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi tải thông tin: $e')),
      );
    }
  }

  List<ChatMember> _asMembers(List<ChatUser> users) => users
      .map((user) => user is ChatMember
          ? user
          : ChatMember(
              id: user.id,
              displayName: user.displayName,
              avatarUrl: user.avatarUrl,
              acsUserId: user.acsUserId,
              email: user.email,
            ))
      .toList();

  @override
  Widget build(BuildContext context) {
    final uiConfig = ref.watch(chatUiConfigProvider);
    // Ưu tiên loại phòng lấy trực tiếp từ join-room. `roomType` truyền từ
    // ThreadScreen có thể bị fallback thành direct khi danh sách conversation
    // chưa load xong, làm toàn bộ UI thành viên/quản trị nhóm bị ẩn.
    final isGroup = _roomDetails?.type == ConversationType.group ||
        widget.roomType == ConversationType.group;

    return Scaffold(
      backgroundColor: uiConfig.roomBackgroundColor ?? const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(
          'Tùy chọn',
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  _buildRoomHeader(uiConfig, isGroup),
                  if (isGroup) _buildGroupQuickActions(uiConfig),
                  if (isGroup) _buildGroupInfoRows(uiConfig),
                  const SizedBox(height: 10),
                  if (isGroup) ...[
                    _buildMemberListSection(uiConfig),
                    const SizedBox(height: 10),
                    _buildDangerZoneSection(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildGroupQuickActions(ChatUiConfig config) {
    final iconColor = config.actionIconColor ?? Colors.black87;
    final items = [
      (Icons.search, 'Tìm\ntin nhắn'),
      (Icons.group_add_outlined, 'Thêm\nthành viên'),
      (Icons.wallpaper_outlined, 'Đổi\nhình nền'),
      (Icons.notifications_none, 'Tắt\nthông báo'),
    ];
    return Material(
      color: config.surfaceColor ?? Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final item in items)
              Expanded(
                child: InkWell(
                  onTap: item.$1 == Icons.group_add_outlined
                      ? _showAddParticipantsDialog
                      : () => showChatFeatureComingSoon(
                            context,
                            feature: item.$2.replaceAll('\n', ' '),
                            config: config,
                          ),
                  borderRadius: BorderRadius.circular(14),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: config.actionIconBackgroundColor ??
                            const Color(0xFFF5F6FA),
                        child: Icon(item.$1, color: iconColor, size: 29),
                      ),
                      const SizedBox(height: 8),
                      Text(item.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, height: 1.15)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupInfoRows(ChatUiConfig config) {
    final iconColor = config.actionIconColor ?? Colors.blueGrey;
    final rows = [
      (Icons.info_outline, 'Thêm mô tả nhóm'),
      (Icons.photo_library_outlined, 'Ảnh, file, link'),
      (Icons.event_outlined, 'Lịch nhóm'),
      (Icons.push_pin_outlined, 'Tin nhắn đã ghim'),
      (Icons.poll_outlined, 'Bình chọn'),
    ];
    return Material(
      color: config.surfaceColor ?? Colors.white,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        child: Column(
          children: [
            for (final row in rows)
              ListTile(
                leading: Icon(row.$1, color: iconColor, size: 28),
                title: Text(row.$2, style: const TextStyle(fontSize: 16)),
                trailing: Icon(Icons.chevron_right, color: iconColor),
                onTap: () => showChatFeatureComingSoon(
                  context,
                  feature: row.$2,
                  config: config,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomHeader(ChatUiConfig uiConfig, bool isGroup) {
    final otherMember = !isGroup
        ? _members
            .where((member) => member.id != widget.currentUserId)
            .firstOrNull
        : null;
    final displayName = isGroup
        ? (_roomDetails?.roomName.isNotEmpty == true
            ? _roomDetails!.roomName
            : 'Nhóm chat')
        : (otherMember?.displayName.isNotEmpty == true
            ? otherMember!.displayName
            : (_roomDetails?.roomName.isNotEmpty == true
                ? _roomDetails!.roomName
                : 'Người dùng'));
    final avatarUrl = isGroup
        ? _roomDetails?.avatarUrl
        : (isNetworkAvatar(otherMember?.avatarUrl)
            ? otherMember?.avatarUrl
            : _roomDetails?.avatarUrl);
    final hasAvatar = isNetworkAvatar(avatarUrl);

    final surface = uiConfig.surfaceColor ?? Colors.white;
    final primary =
        uiConfig.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    final secondary = uiConfig.secondaryTextColor ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      width: double.infinity,
      color: surface,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundImage: hasAvatar ? NetworkImage(avatarUrl!) : null,
                child: !hasAvatar
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 32),
                      )
                    : null,
              ),
              if (isGroup && _isAdmin)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Material(
                    color: primary,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Đổi ảnh nhóm',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.camera_alt_outlined,
                          color: Colors.white, size: 16),
                      onPressed: _pickAndUpdateRoomAvatar,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (isGroup && _isAdmin)
                IconButton(
                  tooltip: 'Đổi tên nhóm',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_outlined, color: primary, size: 20),
                  onPressed: _showEditRoomInfoDialog,
                ),
            ],
          ),
          Text(
            isGroup
                ? 'Nhóm trò chuyện • ${_members.length} thành viên'
                : 'Trò chuyện cá nhân',
            style: TextStyle(color: secondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpdateRoomAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final picked = result?.files.firstOrNull;
    final path = picked?.path;
    if (picked == null || path == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final avatarUrl = await ref.read(uploadRoomAvatarUseCaseProvider)(
        filePath: path,
        filename: picked.name,
      );
      final success = await ref.read(updateRoomInfoUseCaseProvider)(
        roomId: widget.roomId,
        roomName: _roomDetails?.roomName ?? '',
        avatarUrl: avatarUrl,
        roomType: 'G',
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (success) {
        await _loadData();
        widget.onSystemMessage?.call('Ảnh nhóm đã được cập nhật');
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã cập nhật ảnh nhóm',
            config: ref.read(chatUiConfigProvider),
          );
        }
      } else {
        throw StateError('Không thể cập nhật ảnh nhóm');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      showChatToast(
        context,
        message: 'Không thể cập nhật ảnh nhóm: $e',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }

  Widget _buildMemberListSection(ChatUiConfig uiConfig) {
    final primary =
        uiConfig.primaryActionColor ?? Theme.of(context).colorScheme.primary;
    return Material(
      color: uiConfig.surfaceColor ?? Colors.white,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Thành viên',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
              const Divider(),
              if (_members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Center(
                    child: Text(
                      'Chưa tải được danh sách thành viên',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final isMe = member.id == widget.currentUserId;
                    final hasAvatar = isNetworkAvatar(member.avatarUrl);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            hasAvatar ? NetworkImage(member.avatarUrl!) : null,
                        child: !hasAvatar
                            ? Text(member.displayName.isNotEmpty
                                ? member.displayName[0].toUpperCase()
                                : '?')
                            : null,
                      ),
                      title: Text(member.displayName + (isMe ? ' (Bạn)' : '')),
                      subtitle: member.isAdmin
                          ? Text(
                              'Trưởng nhóm',
                              style: TextStyle(
                                color: primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: _isAdmin && !isMe
                          ? PopupMenuButton<String>(
                              onSelected: (value) =>
                                  _handleMemberAction(value, member),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'transfer',
                                  child: ChatActionMenuTile(
                                    icon: Icons.admin_panel_settings_outlined,
                                    label: 'Chuyển quyền Admin',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: ChatActionMenuTile(
                                    icon: Icons.person_remove_outlined,
                                    label: 'Xóa khỏi nhóm',
                                    color: uiConfig.dangerColor ?? Colors.red,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDangerZoneSection() {
    final config = ref.read(chatUiConfigProvider);
    final danger = config.dangerColor ?? Colors.redAccent;
    return Material(
      color: config.surfaceColor ?? Colors.white,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              ListTile(
                leading: Icon(Icons.exit_to_app, color: danger),
                title: Text(
                  'Rời khỏi phòng',
                  style: TextStyle(color: danger, fontWeight: FontWeight.bold),
                ),
                onTap: _showLeaveGroupConfirmDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleMemberAction(String action, ChatMember member) {
    if (action == 'transfer') {
      _showTransferOwnershipConfirmDialog(member);
    } else if (action == 'remove') {
      _showRemoveMemberConfirmDialog(member);
    }
  }

  Future<void> _showEditRoomInfoDialog() async {
    final name = await showChatTextInputDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Đổi tên nhóm',
      hintText: 'Tên nhóm',
      description:
          'Bạn có chắc chắn muốn đổi tên nhóm không? Khi xác nhận tên nhóm mới sẽ hiển thị với tất cả thành viên.',
      initialValue: _roomDetails?.roomName ?? '',
    );
    if (name != null && mounted) _updateRoomInfo(name);
  }

  Future<void> _updateRoomInfo(String newName) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final updateRoomUseCase = ref.read(updateRoomInfoUseCaseProvider);
      final success = await updateRoomUseCase(
        roomId: widget.roomId,
        roomName: newName,
        avatarUrl: _roomDetails?.avatarUrl,
        roomType: 'G',
      );

      if (mounted) {
        Navigator.pop(context); // Tắt loading
      }

      if (success) {
        await _loadData();
        widget.onSystemMessage
            ?.call('Tên nhóm đã được đổi thành "**$newName**"');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể sửa thông tin phòng')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _showTransferOwnershipConfirmDialog(ChatMember member) async {
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Chuyển quyền Admin',
      message:
          'Bạn có chắc chắn muốn chuyển quyền trưởng nhóm cho ${member.displayName}? Sau khi chuyển, bạn sẽ không còn là Admin nữa.',
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
      final transferOwnershipUseCase =
          ref.read(transferOwnershipUseCaseProvider);
      final success = await transferOwnershipUseCase(
        roomId: widget.roomId,
        toUserId: toUserId,
      );

      if (mounted) {
        Navigator.pop(context); // Tắt loading
      }

      if (success) {
        await _loadData();
        final member = _members.where((m) => m.id == toUserId).firstOrNull;
        widget.onSystemMessage?.call(
            '**${member?.displayName ?? 'Thành viên'}** đã được chuyển quyền Admin');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể chuyển quyền Admin')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
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
      final removeParticipantsUseCase =
          ref.read(removeParticipantsUseCaseProvider);
      final removedCount = await removeParticipantsUseCase(
        roomId: widget.roomId,
        participantIds: [userId],
      );

      if (mounted) {
        Navigator.pop(context); // Tắt loading
      }

      if (removedCount > 0) {
        final removed = _members.where((m) => m.id == userId).firstOrNull;
        await _loadData();
        widget.onSystemMessage?.call(
            '**${removed?.displayName ?? 'Thành viên'}** đã bị xóa khỏi nhóm');
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã xóa thành viên khỏi nhóm',
            config: ref.read(chatUiConfigProvider),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể xóa thành viên')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  void _showAddParticipantsDialog() async {
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
      final addParticipantsUseCase = ref.read(addParticipantsUseCaseProvider);
      final addedCount = await addParticipantsUseCase(
        roomId: widget.roomId,
        participantIds: userIds,
      );

      if (mounted) {
        Navigator.pop(context); // Tắt loading
      }

      if (addedCount > 0) {
        await _loadData();
        final names = _members
            .where((m) => userIds.contains(m.id))
            .map((m) => m.displayName)
            .where((name) => name.isNotEmpty)
            .join(', ');
        widget.onSystemMessage?.call(
            '**${names.isEmpty ? 'Thành viên' : names}** đã được thêm vào nhóm');
        if (mounted) {
          showChatToast(
            context,
            message: 'Đã thêm thành viên vào nhóm',
            config: ref.read(chatUiConfigProvider),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể thêm thành viên')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  void _showLeaveGroupConfirmDialog() {
    final otherMembers =
        _members.where((m) => m.id != widget.currentUserId).toList();

    if (_isAdmin && otherMembers.isNotEmpty) {
      _showLeaveAndTransferAdminDialog(otherMembers);
    } else {
      _showStandardLeaveConfirmDialog();
    }
  }

  void _showLeaveAndTransferAdminDialog(List<ChatMember> otherMembers) {
    String? selectedUserId = otherMembers.first.id;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Chọn trưởng nhóm mới'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bạn đang là Admin. Vui lòng chọn thành viên tiếp quản quyền Admin trước khi rời nhóm:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final member in otherMembers)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                selectedUserId == member.id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selectedUserId == member.id
                                    ? (ref
                                            .read(chatUiConfigProvider)
                                            .primaryActionColor ??
                                        Theme.of(context).colorScheme.primary)
                                    : Colors.grey,
                              ),
                              title: Text(member.displayName),
                              subtitle: isNetworkAvatar(member.avatarUrl)
                                  ? null
                                  : (member.email != null &&
                                          member.email!.isNotEmpty
                                      ? Text(member.email!,
                                          style: const TextStyle(fontSize: 12))
                                      : null),
                              onTap: () {
                                setDialogState(() {
                                  selectedUserId = member.id;
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    if (selectedUserId != null) {
                      _leaveRoom(newAdminUserId: selectedUserId);
                    }
                  },
                  child: const Text('Chuyển quyền & Rời'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showStandardLeaveConfirmDialog() async {
    final config = ref.read(chatUiConfigProvider);
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: config,
      title: 'Rời khỏi phòng',
      message: 'Bạn có chắc chắn muốn rời khỏi phòng chat này không?',
      confirmLabel: 'Rời phòng',
      destructive: true,
    );
    if (confirmed && mounted) {
      _leaveRoom();
    }
  }

  Future<void> _leaveRoom({String? newAdminUserId}) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final leaveRoomUseCase = ref.read(leaveRoomUseCaseProvider);
      final success = await leaveRoomUseCase(
        roomId: widget.roomId,
        newAdminUserId: newAdminUserId,
      );

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading dialog

      if (success) {
        showChatToast(
          context,
          message: 'Đã rời khỏi phòng chat',
          config: ref.read(chatUiConfigProvider),
        );
        Navigator.pop(context, true); // Pop màn hình Tùy chọn với kết quả true
        ref.read(conversationListProvider.notifier).removeRoom(widget.roomId);
      } else {
        showChatToast(
          context,
          message: 'Không thể rời phòng chat',
          isError: true,
          config: ref.read(chatUiConfigProvider),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading dialog
      showChatToast(
        context,
        message: 'Lỗi khi rời phòng: $e',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
    }
  }
}
