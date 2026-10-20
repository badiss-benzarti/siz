import 'package:flutter/material.dart';

/// One tab of [RoomNavigationBar].
class RoomNavItem {
  const RoomNavItem(this.icon, this.activeIcon, this.label);

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Rounded, outlined tab bar shared by the owner, barber and client apps.
/// The middle item is the home button (the floor, the salon, the salons),
/// drawn as a round outlined button.
class RoomNavigationBar extends StatelessWidget {
  const RoomNavigationBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length % 2 == 1, 'The home item needs a middle slot.');

  final List<RoomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const _ink = Color(0xFF111111);
  static const _muted = Color(0xFF6B7280);

  int get homeIndex => items.length ~/ 2;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: _ink, width: 2),
          left: BorderSide(color: _ink, width: 2),
          right: BorderSide(color: _ink, width: 2),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: i == homeIndex ? _homeButton() : _item(i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item(int index) {
    final item = items[index];
    final selected = currentIndex == index;
    return Semantics(
      selected: selected,
      button: true,
      child: InkResponse(
        onTap: () => onTap(index),
        radius: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? item.activeIcon : item.icon,
                size: 28,
                color: selected ? _ink : _muted,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected ? _ink : _muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeButton() {
    final item = items[homeIndex];
    final selected = currentIndex == homeIndex;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: GestureDetector(
        onTap: () => onTap(homeIndex),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: selected ? _ink : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: _ink, width: 2),
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                color: selected ? Colors.white : _ink,
                size: 26,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
