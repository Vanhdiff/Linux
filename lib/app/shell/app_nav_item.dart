import 'package:fluent_ui/fluent_ui.dart';

class AppNavItem {
  final String key;
  final String label;
  final String route;
  final IconData icon;
  final bool isUtility;

  const AppNavItem({
    required this.key,
    required this.label,
    required this.route,
    required this.icon,
    this.isUtility = false,
  });
}
