import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';

class JournalSectionLabel extends StatelessWidget {
  final String text;

  const JournalSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class JournalComboField extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onAdd;

  const JournalComboField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return JournalFieldShell(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: ComboBox<String>(
              value: items.contains(value) ? value : null,
              placeholder: Text(value.isEmpty ? 'Select' : value),
              isExpanded: true,
              items: items
                  .map((item) => ComboBoxItem(value: item, child: Text(item)))
                  .toList(),
              onChanged: (nextValue) {
                if (nextValue != null) {
                  onChanged(nextValue);
                }
              },
            ),
          ),
          if (onAdd != null) ...[
            SizedBox(width: 8),
            _ComboAddButton(label: label, onAdd: onAdd!),
          ],
        ],
      ),
    );
  }
}

class _ComboAddButton extends StatelessWidget {
  final String label;
  final ValueChanged<String> onAdd;

  const _ComboAddButton({required this.label, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: () => _showAddDialog(context),
      style: ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.all(8))),
      child: Icon(FluentIcons.add, size: 13, color: AppColors.primary),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return ContentDialog(
          constraints: BoxConstraints(maxWidth: 360),
          title: Text('Add option', style: TextStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: AppColors.textSecondary)),
              SizedBox(height: 8),
              TextBox(
                controller: controller,
                autofocus: true,
                placeholder: 'Type a new option',
                onSubmitted: (_) {
                  Navigator.pop(dialogContext, controller.text.trim());
                },
              ),
            ],
          ),
          actions: [
            Button(
              child: Text('Cancel'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            FilledButton(
              child: Text('Add'),
              onPressed: () {
                Navigator.pop(dialogContext, controller.text.trim());
              },
            ),
          ],
        );
      },
    );
    controller.dispose();
    final normalized = value?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      onAdd(normalized);
    }
  }
}

class JournalFieldShell extends StatelessWidget {
  final String label;
  final Widget child;

  const JournalFieldShell({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [JournalSectionLabel(label), child],
    );
  }
}

class JournalMiniTag extends StatelessWidget {
  final String label;
  final bool removable;
  final bool selected;
  final VoidCallback? onPressed;

  const JournalMiniTag(
    this.label, {
    super.key,
    this.removable = false,
    this.selected = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.primarySoft : AppColors.shellBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (removable) ...[
            SizedBox(width: 6),
            Icon(
              FluentIcons.cancel,
              size: 10,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ],
        ],
      ),
    );
    if (onPressed == null) return content;
    return GestureDetector(onTap: onPressed, child: content);
  }
}

class JournalOutlineAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const JournalOutlineAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: onPressed ?? () {},
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          SizedBox(width: 6),
          Text(label, style: TextStyle(color: AppColors.primary, fontSize: 12)),
        ],
      ),
    );
  }
}

class JournalPill extends StatelessWidget {
  final Widget child;

  const JournalPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.shellBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DefaultTextStyle(
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        child: child,
      ),
    );
  }
}
