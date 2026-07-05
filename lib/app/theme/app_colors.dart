import 'package:fluent_ui/fluent_ui.dart';

import 'app_theme_palette.dart';

abstract class AppColors {
  static AppThemePalette _palette = AppThemePalettes.light;

  static AppThemePalette get palette => _palette;

  static bool get isDark => _palette.mode == AppThemeMode.dark;

  static void use(AppThemePalette palette) {
    _palette = palette;
  }

  static Color get bg => _palette.bg;
  static Color get shellBg => _palette.shellBg;
  static Color get sidebar => _palette.sidebar;
  static Color get surface => _palette.surface;
  static Color get surfaceAlt => _palette.surfaceAlt;
  static Color get border => _palette.border;

  static Color get primary => _palette.primary;
  static Color get primarySoft => _palette.primarySoft;
  static Color get accent => _palette.accent;

  static Color get textPrimary => _palette.textPrimary;
  static Color get textSecondary => _palette.textSecondary;
  static Color get hover => _palette.hover;

  static Color get success => _palette.success;
  static Color get danger => _palette.danger;
  static Color get warning => _palette.warning;
}
