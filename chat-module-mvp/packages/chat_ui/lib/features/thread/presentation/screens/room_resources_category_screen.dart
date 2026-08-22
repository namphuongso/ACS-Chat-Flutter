import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/chat_ui_config.dart';
import '../providers/thread_providers.dart';
import '../widgets/file_resource_tab.dart';
import '../widgets/link_resource_tab.dart';
import '../widgets/media_resource_tab.dart';

class RoomResourcesCategoryScreen extends ConsumerStatefulWidget {
  const RoomResourcesCategoryScreen({
    super.key,
    required this.roomId,
    this.initialCategory = RoomResourceCategory.media,
  });

  final String roomId;
  final RoomResourceCategory initialCategory;

  @override
  ConsumerState<RoomResourcesCategoryScreen> createState() =>
      _RoomResourcesCategoryScreenState();
}

class _RoomResourcesCategoryScreenState
    extends ConsumerState<RoomResourcesCategoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialCategory == RoomResourceCategory.media
        ? 0
        : (widget.initialCategory == RoomResourceCategory.file ? 1 : 2);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiConfig = ref.watch(chatUiConfigProvider);
    final appBarBg = uiConfig.appBarBackgroundColor ?? const Color(0xFF0787E8);
    final isDarkBg =
        ThemeData.estimateBrightnessForColor(appBarBg) == Brightness.dark;
    final titleTextColor =
        uiConfig.appBarIconColor ?? (isDarkBg ? Colors.white : Colors.black87);
    final unselectedTabColor = isDarkBg ? Colors.white70 : Colors.black54;
    final indicatorColor = isDarkBg
        ? Colors.white
        : (uiConfig.primaryActionColor ?? Theme.of(context).primaryColor);

    return Scaffold(
      backgroundColor: uiConfig.surfaceColor ?? const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: Text(
          'Tài nguyên phòng chat',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: titleTextColor,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        backgroundColor: appBarBg,
        iconTheme: IconThemeData(color: titleTextColor),
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: titleTextColor,
          unselectedLabelColor: unselectedTabColor,
          indicatorColor: indicatorColor,
          indicatorWeight: 3,
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: const [
            Tab(text: 'Ảnh & Video'),
            Tab(text: 'File'),
            Tab(text: 'Link'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          MediaResourceTab(roomId: widget.roomId),
          FileResourceTab(roomId: widget.roomId),
          LinkResourceTab(roomId: widget.roomId),
        ],
      ),
    );
  }
}
