import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/i18n/app_localization.dart';
import '../../../../app/theme/app_colors.dart';

class NewsHeader extends StatelessWidget {
  final NewsViewMode selectedMode;
  final ValueChanged<NewsViewMode> onModeChanged;
  final VoidCallback? onRefresh;

  const NewsHeader({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _HeaderActions(
        selectedMode: selectedMode,
        onModeChanged: onModeChanged,
        onRefresh: onRefresh,
      ),
    );
  }
}

enum NewsViewMode { list, calendar }

class _HeaderActions extends StatelessWidget {
  final NewsViewMode selectedMode;
  final ValueChanged<NewsViewMode> onModeChanged;
  final VoidCallback? onRefresh;

  const _HeaderActions({
    required this.selectedMode,
    required this.onModeChanged,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return Row(
      children: [
        _ModeButton(
          icon: FluentIcons.list,
          label: strings.text('List'),
          selected: selectedMode == NewsViewMode.list,
          onTap: () => onModeChanged(NewsViewMode.list),
        ),
        SizedBox(width: 8),
        _ModeButton(
          icon: FluentIcons.calendar,
          label: strings.text('Calendar'),
          selected: selectedMode == NewsViewMode.calendar,
          onTap: () => onModeChanged(NewsViewMode.calendar),
        ),
        SizedBox(width: 8),
        _RefreshButton(onTap: onRefresh),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      builder: (hovering, pressing) {
        final active = selected || hovering;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary
                : hovering
                ? AppColors.primarySoft
                : AppColors.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
            boxShadow: hovering && !selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _RefreshButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalization.of(context);
    return _Pressable(
      onTap: onTap,
      builder: (hovering, pressing) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovering ? AppColors.primarySoft : AppColors.surface,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: hovering ? AppColors.primary : AppColors.border,
            ),
            boxShadow: hovering
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Icon(FluentIcons.refresh, size: 14, color: AppColors.primary),
              SizedBox(width: 7),
              Text(
                strings.text('Refresh'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Pressable extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget Function(bool hovering, bool pressing) builder;

  const _Pressable({required this.builder, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hovering = false;
  bool _pressing = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = enabled),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressing = false;
      }),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: enabled ? (_) => setState(() => _pressing = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressing = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressing = false) : null,
        child: AnimatedScale(
          scale: _pressing ? 0.96 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: widget.builder(_hovering, _pressing),
        ),
      ),
    );
  }
}
