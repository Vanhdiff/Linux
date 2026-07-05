import 'package:fluent_ui/fluent_ui.dart';
import 'app_colors.dart';

FluentThemeData buildAppTheme() {
  return FluentThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    accentColor: AccentColor.swatch({
      'darkest': AppColors.primary,
      'darker': AppColors.primary,
      'dark': AppColors.primary,
      'normal': AppColors.primary,
      'light': AppColors.primary,
      'lighter': AppColors.primary,
      'lightest': AppColors.primary,
    }),
  );
}
