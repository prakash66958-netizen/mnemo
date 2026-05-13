import 'package:flutter/material.dart';

/// Custom bottom navigation bar. Each tab has an icon inside a pill
/// ("indicator") that lights up with the primary container color when active.
/// Mirrors `.nav` + `.tab` / `.pill` from the HTML mockup.
class MnemoNavBar extends StatelessWidget {
  const MnemoNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;
  final List<MnemoNavItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The system gesture / navigation inset varies across devices (0 on
    // older phones, ~24–48px on modern gesture-nav phones). We must add it
    // to our bar height instead of letting SafeArea push the inner content
    // past a fixed height — that's what caused the "Bottom overflowed by
    // 29px" warning.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: 68 + bottomInset,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: bottomInset,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _NavTab(
                item: items[i],
                active: i == currentIndex,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class MnemoNavItem {
  const MnemoNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final MnemoNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pillBg = active ? scheme.primaryContainer : Colors.transparent;
    final pillFg = active
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    final labelFg = active ? scheme.onSurface : scheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 56,
            height: 30,
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              active ? item.activeIcon : item.icon,
              size: 22,
              color: pillFg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelFg,
            ),
          ),
        ],
      ),
    );
  }
}
