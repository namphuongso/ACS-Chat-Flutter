import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

class ReactionPickerItem extends StatelessWidget {
  const ReactionPickerItem({
    super.key,
    required this.reaction,
    required this.isSelected,
    required this.isHovered,
    required this.primaryColor,
    required this.onHover,
    required this.onTap,
  });

  final ReactionConfig reaction;
  final bool isSelected;
  final bool isHovered;
  final Color primaryColor;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: Tooltip(
        message: reaction.displayName,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: AnimatedScale(
                scale: isHovered ? 1.45 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutBack,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 36,
                  height: 36,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.15)
                        : Colors.transparent,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: primaryColor, width: 1.5)
                        : null,
                  ),
                  child: reaction.iconUrl.isEmpty
                      ? const Icon(Icons.emoji_emotions_outlined, size: 24)
                      : Image.network(
                          reaction.iconUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.emoji_emotions_outlined,
                            size: 24,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
