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
import 'room_members_screen.dart';
import '../widgets/room_danger_zone.dart';
import '../widgets/room_header_section.dart';
import '../widgets/room_quick_actions.dart';
import '../widgets/room_resource_preview_section.dart';

class RoomSettingsScreen extends ConsumerStatefulWidget {
  const RoomSettingsScreen({
    super.key,
    required this.roomId,
    required this.currentUserId,
    required this.roomType,
    this.onRoomChanged,
  });

  final String roomId;
  final String currentUserId;
  final ConversationType roomType;
  final ValueChanged<Conversation>? onRoomChanged;

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

      var members = _asMembers(room.participants);
      try {
        final remoteMembers =
            await ref.read(getMembersUseCaseProvider)(widget.roomId);
        if (remoteMembers.isNotEmpty) members = remoteMembers;
      } catch (_) {}

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
    final isGroup = _roomDetails?.type == ConversationType.group ||
        widget.roomType == ConversationType.group;

    return Scaffold(
      backgroundColor: uiConfig.roomBackgroundColor ?? const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: Text(
          isGroup ? 'Thông tin nhóm' : 'Thông tin hội thoại',
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
                  const SizedBox(height: 10),
                  RoomHeaderSection(
                    uiConfig: uiConfig,
                    isGroup: isGroup,
                    isAdmin: _isAdmin,
                    roomDetails: _roomDetails,
                    members: _members,
                    currentUserId: widget.currentUserId,
                    onPickAvatar: _pickAndUpdateRoomAvatar,
                    onEditName: _showEditRoomInfoDialog,
                  ),
                  if (isGroup)
                    RoomQuickActions(
                      config: uiConfig,
                      onSearchTap: () => Navigator.pop(context, 'open_search'),
                      onAddMembersTap: _openMembersScreen,
                    ),
                  if (!isGroup) _buildDirectRoomOptions(uiConfig),
                  RoomResourcePreviewSection(
                    roomId: widget.roomId,
                    extraRows: [
                      if (isGroup) _buildMemberRow(uiConfig),
                    ],
                  ),
                  if (isGroup) ...[
                    const SizedBox(height: 2),
                    RoomDangerZone(
                      config: uiConfig,
                      isGroup: isGroup,
                      isAdmin: _isAdmin,
                      onLeaveTap: _showLeaveGroupConfirmDialog,
                      onDisbandTap: _showDisbandGroupConfirmDialog,
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDirectRoomOptions(ChatUiConfig config) {
    final iconColor = config.actionIconColor ?? Colors.black87;
    final conversations = ref.watch(conversationListProvider);
    final isPinned = conversations
            .where((conversation) => conversation.id == widget.roomId)
            .firstOrNull
            ?.pin ??
        _roomDetails?.pin ??
        false;
    final items = [
      (
        Icons.search,
        'Tìm\ntin nhắn',
        () => Navigator.pop(context, 'open_search'),
      ),
      // (
      //   Icons.notifications_none,
      //   'Tắt\nthông báo',
      //   () => showChatFeatureComingSoon(
      //         context,
      //         feature: 'Tắt thông báo',
      //         config: config,
      //       ),
      // ),
      (
        isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        isPinned ? 'Bỏ ghim\nhội thoại' : 'Ghim\nhội thoại',
        () => _togglePinRoom(isPinned),
      ),
      (
        Icons.group_add_outlined,
        'Tạo cuộc\ntrò chuyện',
        _openCreateConversation,
      ),
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
                  onTap: item.$3,
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

  Future<void> _togglePinRoom(bool currentPin) async {
    final config = ref.read(chatUiConfigProvider);
    final target = !currentPin;
    ref
        .read(conversationListProvider.notifier)
        .updateRoomPin(widget.roomId, target);
    try {
      final ok =
          await ref.read(pinConversationUseCaseProvider)(widget.roomId, target);
      if (!mounted) return;
      if (!ok) {
        ref
            .read(conversationListProvider.notifier)
            .updateRoomPin(widget.roomId, currentPin);
        showChatToast(
          context,
          message: 'Không thể ghim cuộc trò chuyện',
          isError: true,
          config: config,
        );
      } else {
        showChatToast(
          context,
          message:
              target ? 'Đã ghim cuộc trò chuyện' : 'Đã bỏ ghim cuộc trò chuyện',
          config: config,
        );
      }
    } catch (_) {
      if (!mounted) return;
      ref
          .read(conversationListProvider.notifier)
          .updateRoomPin(widget.roomId, currentPin);
      showChatToast(
        context,
        message: 'Không thể ghim lúc này',
        isError: true,
        config: config,
      );
    }
  }

  /// "Tạo cuộc trò chuyện": mở màn chọn danh bạ (đã loại trừ bạn và người
  /// đang chat vì mặc định nằm trong nhóm), sau đó nhập tên và tạo nhóm.
  Future<void> _openCreateConversation() async {
    final other = _members
        .where((member) => member.id != widget.currentUserId)
        .firstOrNull;
    if (other == null) return;

    final selectedIds = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(
        builder: (_) => AddParticipantsScreen(
          currentMembers: _members,
          title: 'Tạo cuộc trò chuyện',
        ),
      ),
    );
    if (selectedIds == null || selectedIds.isEmpty || !mounted) return;

    final groupName = await showChatTextInputDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Tạo cuộc trò chuyện',
      hintText: 'Nhập tên nhóm chat...',
      confirmLabel: 'Tạo',
    );
    if (groupName == null || !mounted) return;

    await _handleCreateConversation(
      selectedIds: selectedIds,
      groupName: groupName,
    );
  }

  Future<void> _handleCreateConversation({
    required List<String> selectedIds,
    required String groupName,
  }) async {
    final config = ref.read(chatUiConfigProvider);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final participantIds = <String>{
        widget.currentUserId,
        ..._members.map((member) => member.id),
        ...selectedIds,
      }.toList();

      final conversation =
          await ref.read(createGroupConversationUseCaseProvider)(
        participantIds: participantIds,
        roomName: groupName,
      );

      if (conversation.token != null &&
          conversation.tokenUtcExp != null &&
          conversation.cui != null) {
        ref.read(authTokenRepositoryProvider).cacheToken(
              conversation.id,
              ChatAccessToken(
                token: conversation.token!,
                expiresOn: conversation.tokenUtcExp!,
                acsUserId: conversation.cui!,
              ),
            );
      }

      ref.read(conversationListProvider.notifier).addOrUpdateRoom(conversation);
      if (!mounted) return;
      Navigator.of(context).pop(); // Tắt loading
      // Trả conversation mới về ThreadScreen để mở luôn cuộc trò chuyện đó.
      Navigator.of(context).pop(conversation);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Tắt loading
      showChatToast(
        context,
        message: 'Không thể tạo cuộc trò chuyện: $e',
        isError: true,
        config: config,
      );
    }
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

      String? avatarTypeCode;
      try {
        final updateTypes = await ref.read(getRoomUpdateTypesUseCaseProvider)();
        final avatarType = updateTypes
            .where((t) => t.code.toLowerCase() == 'avatar')
            .firstOrNull;
        avatarTypeCode = avatarType?.code ?? 'Avatar';
      } catch (_) {
        avatarTypeCode = 'Avatar';
      }

      final success = await ref.read(updateRoomInfoUseCaseProvider)(
        roomId: widget.roomId,
        roomName: _roomDetails?.roomName ?? '',
        avatarUrl: avatarUrl,
        roomType: 'G',
        updateType: avatarTypeCode,
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (success) {
        await _loadData();
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

  /// Dòng "Thành viên" — click mở trang danh sách thành viên của phòng.
  Widget _buildMemberRow(ChatUiConfig uiConfig) {
    final iconColor = uiConfig.actionIconColor ?? Colors.blueGrey;
    final secondary = uiConfig.secondaryTextColor ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      leading: Icon(Icons.people_outline, color: iconColor, size: 28),
      title: const Text('Thành viên', style: TextStyle(fontSize: 16)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_members.length}',
            style: TextStyle(color: secondary, fontSize: 15),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: iconColor),
        ],
      ),
      onTap: _openMembersScreen,
    );
  }

  Future<void> _openMembersScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RoomMembersScreen(
          roomId: widget.roomId,
          currentUserId: widget.currentUserId,
          isAdmin: _isAdmin,
          initialMembers: _members,
          onMembersChanged: (members) {
            if (!mounted) return;
            setState(() {
              _members = members;
              _isAdmin = members
                      .where((member) => member.id == widget.currentUserId)
                      .firstOrNull
                      ?.isAdmin ??
                  false;
            });
            final details = _roomDetails;
            if (details != null) {
              widget.onRoomChanged
                  ?.call(details.copyWith(participants: members));
            }
          },
        ),
      ),
    );
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
      String? nameTypeCode;
      try {
        final updateTypes = await ref.read(getRoomUpdateTypesUseCaseProvider)();
        final nameType = updateTypes
            .where((t) => t.code.toLowerCase() == 'name')
            .firstOrNull;
        nameTypeCode = nameType?.code ?? 'Name';
      } catch (_) {
        nameTypeCode = 'Name';
      }

      final updateRoomUseCase = ref.read(updateRoomInfoUseCaseProvider);
      final success = await updateRoomUseCase(
        roomId: widget.roomId,
        roomName: newName,
        avatarUrl: _roomDetails?.avatarUrl,
        roomType: 'G',
        updateType: nameTypeCode,
      );

      if (mounted) {
        Navigator.pop(context); // Tắt loading
      }

      if (success) {
        await _loadData();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể sửa thông tin phòng')),
          );
        }
      }
    } catch (e, st) {
      ChatLogger.error('Update room info error', error: e, stackTrace: st);
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        showChatToast(
          context,
          message: 'Không thể sửa thông tin phòng',
          isError: true,
          config: ref.read(chatUiConfigProvider),
        );
      }
    }
  }

  Future<void> _showDisbandGroupConfirmDialog() async {
    final confirmed = await showChatConfirmDialog(
      context: context,
      config: ref.read(chatUiConfigProvider),
      title: 'Giải tán nhóm',
      message:
          'Bạn có chắc chắn muốn giải tán nhóm này không? Toàn bộ thành viên sẽ bị xóa khỏi nhóm và không thể khôi phục.',
      confirmLabel: 'Giải tán',
      destructive: true,
    );
    if (confirmed && mounted) _closeRoom();
  }

  Future<void> _closeRoom() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success =
          await ref.read(closeRoomUseCaseProvider)(roomId: widget.roomId);

      if (!mounted) return;
      Navigator.pop(context); // Tắt loading

      if (success) {
        showChatToast(
          context,
          message: 'Đã giải tán nhóm',
          config: ref.read(chatUiConfigProvider),
        );
        Navigator.pop(context, 'room_disbanded');
        Future.microtask(() {
          ref.read(conversationListProvider.notifier).removeRoom(widget.roomId);
        });
      } else {
        showChatToast(
          context,
          message: 'Không thể giải tán nhóm',
          isError: true,
          config: ref.read(chatUiConfigProvider),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Tắt loading
      showChatToast(
        context,
        message: 'Lỗi khi giải tán nhóm: $e',
        isError: true,
        config: ref.read(chatUiConfigProvider),
      );
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
    final config = ref.read(chatUiConfigProvider);
    final primary =
        config.primaryActionColor ?? Theme.of(context).colorScheme.primary;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.admin_panel_settings_rounded,
                            color: primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Chuyển quyền Owner',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Chọn 1 thành viên tiếp quản trước khi rời',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: otherMembers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final member = otherMembers[index];
                          final isSelected = selectedUserId == member.id;
                          final hasAvatar = isNetworkAvatar(member.avatarUrl);
                          final initial = member.displayName.isNotEmpty
                              ? member.displayName[0].toUpperCase()
                              : '?';

                          return InkWell(
                            onTap: () {
                              setSheetState(() {
                                selectedUserId = member.id;
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primary.withValues(alpha: 0.08)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected
                                      ? primary
                                      : Colors.grey.shade200,
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: isSelected
                                        ? primary.withValues(alpha: 0.2)
                                        : Colors.grey.shade300,
                                    backgroundImage: hasAvatar
                                        ? NetworkImage(member.avatarUrl!)
                                        : null,
                                    child: !hasAvatar
                                        ? Text(
                                            initial,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected
                                                  ? primary
                                                  : Colors.black87,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          member.displayName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? primary
                                                : Colors.black87,
                                          ),
                                        ),
                                        if (member.email != null &&
                                            member.email!.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            member.email!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected
                                        ? primary
                                        : Colors.grey.shade400,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(sheetContext),
                            child: Text(
                              'Hủy',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              if (selectedUserId != null) {
                                _leaveRoom(newAdminUserId: selectedUserId);
                              }
                            },
                            child: const Text(
                              'Chuyển quyền & Rời',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
