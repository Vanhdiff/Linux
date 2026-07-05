import 'package:fluent_ui/fluent_ui.dart';

enum AppThemeMode { light, dark }

class AppThemePalette {
  final AppThemeMode mode;
  final String name;
  final String description;
  final Color bg;
  final Color shellBg;
  final Color sidebar;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color primary;
  final Color primarySoft;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color hover;
  final Color success;
  final Color danger;
  final Color warning;

  const AppThemePalette({
    required this.mode,
    required this.name,
    required this.description,
    required this.bg,
    required this.shellBg,
    required this.sidebar,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.primary,
    required this.primarySoft,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.hover,
    required this.success,
    required this.danger,
    required this.warning,
  });
}

abstract final class AppThemePalettes {
  static const light = AppThemePalette(
    mode: AppThemeMode.light,
    name: 'Trắng',
    description: 'Light mode',
    bg: Color(0xFFF3E8FF),
    shellBg: Color(0xFFF7F3FF),
    sidebar: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF7F3FF),
    border: Color(0xFFEEE8F8),
    primary: Color(0xFF8B6CFF),
    primarySoft: Color(0xFFF1EAFF),
    accent: Color(0xFF1FA971),
    textPrimary: Color(0xFF1C1C1E),
    textSecondary: Color(0xFF7E7E87),
    hover: Color(0xFFF1EAFF),
    success: Color(0xFF1FA971),
    danger: Color(0xFFE25555),
    warning: Color(0xFFF5A623),
  );

  static const dark = AppThemePalette(
    mode: AppThemeMode.dark,
    name: 'Đen',
    description: 'VS Code dark',
    bg: Color(0xFF1E1E1E),
    shellBg: Color(0xFF1E1E1E),
    sidebar: Color(0xFF252526),
    surface: Color(0xFF252526),
    surfaceAlt: Color(0xFF2D2D30),
    border: Color(0xFF3C3C3C),
    primary: Color(0xFF007ACC),
    primarySoft: Color(0xFF2A2D2E),
    accent: Color(0xFF007ACC),
    textPrimary: Color(0xFFCCCCCC),
    textSecondary: Color(0xFF858585),
    hover: Color(0xFF2A2D2E),
    success: Color(0xFF89D185),
    danger: Color(0xFFF14C4C),
    warning: Color(0xFFDCDCAA),
  );

  static const all = [light, dark];
}
