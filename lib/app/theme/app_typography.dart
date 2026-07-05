import 'package:fluent_ui/fluent_ui.dart';
import 'app_colors.dart';

abstract class AppTypography {
  static TextStyle pageTitle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle cardTitle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static TextStyle metricValue = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle body = TextStyle(fontSize: 14, color: AppColors.textPrimary);

  static TextStyle muted = TextStyle(
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
