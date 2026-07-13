import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import 'journal_shared_widgets.dart';

class JournalPlanCheckbox extends StatelessWidget {
  final bool followedPlan;
  final ValueChanged<bool> onChanged;

  const JournalPlanCheckbox({
    super.key,
    required this.followedPlan,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalSectionLabel('Plan'),
        Row(
          children: [
            Checkbox(
              checked: followedPlan,
              onChanged: (value) {
                if (value != null) {
                  onChanged(value);
                }
              },
            ),
            const Expanded(child: Text('I followed my trade plan')),
          ],
        ),
      ],
    );
  }
}

class JournalTagSelectorField extends StatelessWidget {
  final String label;
  final List<String> tags;
  final List<String> selectedTags;
  final ValueChanged<String> onToggleTag;
  final String addTitle;
  final ValueChanged<String> onAddTag;
  final bool removableWhenSelected;

  const JournalTagSelectorField({
    super.key,
    required this.label,
    required this.tags,
    required this.selectedTags,
    required this.onToggleTag,
    required this.addTitle,
    required this.onAddTag,
    this.removableWhenSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return JournalFieldShell(
      label: label,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            JournalMiniTag(
              tag,
              selected: selectedTags.contains(tag),
              removable: removableWhenSelected && selectedTags.contains(tag),
              onPressed: () => onToggleTag(tag),
            ),
          JournalAddOptionChip(label: 'Add', title: addTitle, onAdd: onAddTag),
        ],
      ),
    );
  }
}

class JournalAddOptionChip extends StatelessWidget {
  final String label;
  final String title;
  final ValueChanged<String> onAdd;

  const JournalAddOptionChip({
    super.key,
    required this.label,
    required this.title,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: () => _showAddOptionDialog(context),
      style: const ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.add, size: 11, color: AppColors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddOptionDialog(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 360),
          title: Text(title, style: const TextStyle(fontSize: 18)),
          content: TextBox(
            controller: controller,
            autofocus: true,
            placeholder: 'Type a new option',
            onSubmitted: (_) {
              Navigator.pop(dialogContext, controller.text.trim());
            },
          ),
          actions: [
            Button(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(dialogContext),
            ),
            FilledButton(
              child: const Text('Add'),
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
