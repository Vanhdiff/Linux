import 'package:fluent_ui/fluent_ui.dart';
import '../../i18n/app_strings.dart';
import '../app_nav_item.dart';
import '../app_nav_items.dart';
import '../shell_theme.dart';

class ShellSidebar extends StatelessWidget {
  final String currentRoute;
  final bool isCollapsed;
  final AppThemePalette theme;
  final AppStrings strings;
  final bool isBootstrapping;
  final bool backendReady;
  final bool mt5Ready;
  final String? connectionMessage;
  final ValueChanged<String> onNavigate;
  final VoidCallback onToggleCollapsed;

  const ShellSidebar({
    super.key,
    required this.currentRoute,
    required this.isCollapsed,
    required this.theme,
    required this.strings,
    required this.isBootstrapping,
    required this.backendReady,
    required this.mt5Ready,
    required this.connectionMessage,
    required this.onNavigate,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = _SidebarColors(theme);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 64,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(right: BorderSide(color: colors.border)),
        boxShadow: [
          BoxShadow(
            color: const Color(0x0F111827),
            blurRadius: 18,
            offset: const Offset(6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _SidebarBrand(
            theme: theme,
            colors: colors,
            isCollapsed: true,
            onToggleCollapsed: onToggleCollapsed,
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ...AppNavItems.main.map(
                    (item) => _SidebarNavButton(
                      item: item,
                      selected: currentRoute == item.route,
                      isCollapsed: true,
                      theme: theme,
                      colors: colors,
                      strings: strings,
                      onTap: () => onNavigate(item.route),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 1,
            width: 26,
            margin: const EdgeInsets.symmetric(vertical: 14),
            color: colors.border,
          ),
          _SidebarStatus(
            colors: colors,
            isBootstrapping: isBootstrapping,
            backendReady: backendReady,
            mt5Ready: mt5Ready,
            connectionMessage: connectionMessage,
          ),
          Container(
            height: 1,
            width: 26,
            margin: const EdgeInsets.symmetric(vertical: 14),
            color: colors.border,
          ),
          ...AppNavItems.utilities.map(
            (item) => _SidebarNavButton(
              item: item,
              selected: currentRoute == item.route,
              isCollapsed: true,
              theme: theme,
              colors: colors,
              strings: strings,
              onTap: switch (item.key) {
                'collapse' => onToggleCollapsed,
                _ => () => onNavigate(item.route),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarStatus extends StatelessWidget {
  final _SidebarColors colors;
  final bool isBootstrapping;
  final bool backendReady;
  final bool mt5Ready;
  final String? connectionMessage;

  const _SidebarStatus({
    required this.colors,
    required this.isBootstrapping,
    required this.backendReady,
    required this.mt5Ready,
    required this.connectionMessage,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isBootstrapping
        ? const Color(0xFFF59E0B)
        : backendReady && mt5Ready
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final label =
        connectionMessage ??
        (isBootstrapping
            ? 'Starting trading engine'
            : backendReady && mt5Ready
            ? 'MT5 connected'
            : 'MT5 disconnected');

    return Tooltip(
      message: label,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.18)),
        ),
        child: isBootstrapping
            ? SizedBox(
                width: 14,
                height: 14,
                child: ProgressRing(strokeWidth: 2, activeColor: statusColor),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    backendReady && mt5Ready
                        ? FluentIcons.plug_connected
                        : FluentIcons.plug_disconnected,
                    size: 16,
                    color: statusColor,
                  ),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.bg, width: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SidebarColors {
  final AppThemePalette theme;

  const _SidebarColors(this.theme);

  Color get bg => const Color(0xFFFFFFFF);
  Color get bgAlt => const Color(0xFFF3EEFF);
  Color get border => const Color(0xFFE8E2F5);
  Color get text => const Color(0xFF1F2430);
  Color get muted => const Color(0xFF9AA8BD);
  Color get active => theme.primary;
}

class _SidebarBrand extends StatelessWidget {
  final AppThemePalette theme;
  final _SidebarColors colors;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;

  const _SidebarBrand({
    required this.theme,
    required this.colors,
    required this.isCollapsed,
    required this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Trading Desk',
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9A4DFF), Color(0xFFFF6B8B)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: colors.active.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          FluentIcons.cube_shape,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

class _SidebarNavButton extends StatelessWidget {
  final AppNavItem item;
  final bool selected;
  final bool isCollapsed;
  final AppThemePalette theme;
  final _SidebarColors colors;
  final AppStrings strings;
  final VoidCallback onTap;

  const _SidebarNavButton({
    required this.item,
    required this.selected,
    required this.isCollapsed,
    required this.theme,
    required this.colors,
    required this.strings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayIcon = item.key == 'collapse' && isCollapsed
        ? FluentIcons.double_chevron_right
        : item.icon;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                left: selected ? 0 : -4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3,
                  height: selected ? 26 : 0,
                  decoration: BoxDecoration(
                    color: colors.active,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? colors.bgAlt : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  displayIcon,
                  size: item.key == 'collapse' ? 14 : 18,
                  color: selected ? colors.active : colors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Tooltip(message: strings.nav(item.key, item.label), child: child);
  }
}
