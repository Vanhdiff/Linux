import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../guardrails_defaults.dart';

class GuardrailsTimeZoneBadge extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double fontSize;

  const GuardrailsTimeZoneBadge({
    super.key,
    this.width = 58,
    this.height = 28,
    this.radius = 8,
    this.fontSize = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        GuardrailsDefaults.tradingWindowTimeZone,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
