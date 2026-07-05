import 'package:fluent_ui/fluent_ui.dart';
import '../router/route_names.dart';
import 'app_nav_item.dart';

abstract class AppNavItems {
  static const List<AppNavItem> main = [
    AppNavItem(
      key: 'dashboard',
      label: 'Dashboard',
      route: RouteNames.dashboard,
      icon: FluentIcons.view_dashboard,
    ),
    AppNavItem(
      key: 'journal',
      label: 'Journal',
      route: RouteNames.journal,
      icon: FluentIcons.edit_note,
    ),
    AppNavItem(
      key: 'notebook',
      label: 'Notebook',
      route: RouteNames.notebook,
      icon: FluentIcons.memo,
    ),
    AppNavItem(
      key: 'news',
      label: 'News',
      route: RouteNames.news,
      icon: FluentIcons.news,
    ),
    AppNavItem(
      key: 'guardrails',
      label: 'Guardrails',
      route: RouteNames.guardrails,
      icon: FluentIcons.shield,
    ),
    AppNavItem(
      key: 'aiCoach',
      label: 'AI Coach',
      route: RouteNames.aiCoach,
      icon: FluentIcons.robot,
    ),
  ];

  static const List<AppNavItem> utilities = [
    AppNavItem(
      key: 'collapse',
      label: 'Collapse',
      route: '/collapse',
      icon: FluentIcons.double_chevron_left_med,
      isUtility: true,
    ),
    AppNavItem(
      key: 'settings',
      label: 'Settings',
      route: RouteNames.settings,
      icon: FluentIcons.settings,
      isUtility: true,
    ),
  ];
}
