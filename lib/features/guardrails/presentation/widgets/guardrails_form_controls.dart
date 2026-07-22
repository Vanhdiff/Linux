import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';

class GuardrailsTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;
  final double width;
  final double height;
  final bool enabled;
  final double fontSize;
  final double borderRadius;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  const GuardrailsTextField({
    super.key,
    required this.controller,
    this.prefix,
    this.suffix,
    this.width = 116,
    this.height = 36,
    this.enabled = true,
    this.fontSize = 12,
    this.borderRadius = 9,
    this.fontWeight = FontWeight.w700,
    this.textAlign = TextAlign.right,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: TextBox(
        controller: controller,
        enabled: enabled,
        prefix: prefix == null ? null : _FieldAffix(prefix!, fontSize: fontSize),
        suffix: suffix == null ? null : _FieldAffix(suffix!, fontSize: fontSize),
        textAlign: textAlign,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
        decoration: WidgetStatePropertyAll(
          BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}

class GuardrailsSelect extends StatelessWidget {
  final String value;
  final List<String> values;
  final ValueChanged<String>? onChanged;
  final double width;
  final double height;
  final TextOverflow itemOverflow;

  const GuardrailsSelect({
    super.key,
    required this.value,
    required this.values,
    required this.onChanged,
    required this.width,
    this.height = 36,
    this.itemOverflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ComboBox<String>(
        value: value,
        items: values
            .map(
              (item) => ComboBoxItem<String>(
                value: item,
                child: Text(item, overflow: itemOverflow),
              ),
            )
            .toList(),
        onChanged: onChanged == null
            ? null
            : (next) {
                if (next != null) onChanged?.call(next);
              },
      ),
    );
  }
}

class GuardrailsMoneyInput extends StatelessWidget {
  final TextEditingController controller;
  final double inputWidth;
  final double height;
  final double fontSize;
  final double borderRadius;
  final bool enabled;

  const GuardrailsMoneyInput({
    super.key,
    required this.controller,
    this.inputWidth = 104,
    this.height = 36,
    this.fontSize = 12,
    this.borderRadius = 7,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          r'$',
          style: TextStyle(
            fontSize: fontSize,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 6),
        GuardrailsTextField(
          controller: controller,
          width: inputWidth,
          height: height,
          fontSize: fontSize,
          borderRadius: borderRadius,
          enabled: enabled,
        ),
      ],
    );
  }
}

class GuardrailsRecommendedBadge extends StatelessWidget {
  final String label;

  const GuardrailsRecommendedBadge({
    super.key,
    this.label = 'Recommended',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _FieldAffix extends StatelessWidget {
  final String text;
  final double fontSize;

  const _FieldAffix(this.text, {required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
