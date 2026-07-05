import 'package:fluent_ui/fluent_ui.dart';

import '../shell_theme.dart';

class ThemePickerBar extends StatelessWidget {
  final List<AppThemePalette> presets;
  final AppThemePalette selected;
  final ValueChanged<AppThemePalette> onSelected;
  final VoidCallback onClose;

  const ThemePickerBar({
    super.key,
    required this.presets,
    required this.selected,
    required this.onSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: selected.surface.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected.border),
        boxShadow: [
          BoxShadow(
            color: selected.primary.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Theme',
                  style: TextStyle(
                    color: selected.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected.hover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected.border),
                  ),
                  child: Icon(
                    FluentIcons.cancel,
                    size: 11,
                    color: selected.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...presets.map(
            (preset) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ThemePresetChip(
                preset: preset,
                selected: preset.name == selected.name,
                textPrimary: selected.textPrimary,
                textSecondary: selected.textSecondary,
                onTap: () => onSelected(preset),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemePresetChip extends StatelessWidget {
  final AppThemePalette preset;
  final bool selected;
  final Color textPrimary;
  final Color textSecondary;
  final VoidCallback onTap;

  const _ThemePresetChip({
    required this.preset,
    required this.selected,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? preset.hover : preset.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? preset.primary : preset.border,
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Row(
          children: [
            _ThemeSwatches(preset: preset),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (selected)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: preset.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preset.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? preset.primary : textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatches extends StatelessWidget {
  final AppThemePalette preset;

  const _ThemeSwatches({required this.preset});

  @override
  Widget build(BuildContext context) {
    final swatches = [preset.bg, preset.shellBg, preset.primary, preset.accent];

    return SizedBox(
      width: 38,
      height: 28,
      child: Stack(
        children: [
          for (var index = 0; index < swatches.length; index++)
            Positioned(
              left: index * 8,
              child: Container(
                width: 18,
                height: 28,
                decoration: BoxDecoration(
                  color: swatches[index],
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
