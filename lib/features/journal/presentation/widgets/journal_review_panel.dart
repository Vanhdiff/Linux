import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import 'journal_shared_widgets.dart';

class JournalReviewPanel extends StatelessWidget {
  final TextEditingController reflectionController;
  final bool followedPlan;
  final ValueChanged<bool> onFollowedPlanChanged;
  final String entryPlan;
  final List<String> plans;
  final ValueChanged<String> onEntryPlanChanged;
  final ValueChanged<String> onAddPlan;
  final String entryConfluence;
  final List<String> confluences;
  final ValueChanged<String> onEntryConfluenceChanged;
  final ValueChanged<String> onAddConfluence;
  final String entryEmotion;
  final String exitEmotion;
  final List<String> emotions;
  final ValueChanged<String> onEntryEmotionChanged;
  final ValueChanged<String> onExitEmotionChanged;
  final ValueChanged<String> onAddEmotion;
  final List<String> managementTags;
  final List<String> selectedManagementTags;
  final ValueChanged<String> onToggleManagementTag;
  final ValueChanged<String> onAddManagementTag;
  final List<String> mistakeTags;
  final List<String> selectedMistakes;
  final ValueChanged<String> onToggleMistake;
  final ValueChanged<String> onAddMistake;
  final bool saving;
  final String? notice;
  final VoidCallback onSave;

  const JournalReviewPanel({
    super.key,
    required this.reflectionController,
    required this.followedPlan,
    required this.onFollowedPlanChanged,
    required this.entryPlan,
    required this.plans,
    required this.onEntryPlanChanged,
    required this.onAddPlan,
    required this.entryConfluence,
    required this.confluences,
    required this.onEntryConfluenceChanged,
    required this.onAddConfluence,
    required this.entryEmotion,
    required this.exitEmotion,
    required this.emotions,
    required this.onEntryEmotionChanged,
    required this.onExitEmotionChanged,
    required this.onAddEmotion,
    required this.managementTags,
    required this.selectedManagementTags,
    required this.onToggleManagementTag,
    required this.onAddManagementTag,
    required this.mistakeTags,
    required this.selectedMistakes,
    required this.onToggleMistake,
    required this.onAddMistake,
    required this.saving,
    required this.notice,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review & Reflection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (notice != null) ...[
                Text(
                  notice!,
                  style: TextStyle(
                    color: notice!.startsWith('Could not')
                        ? AppColors.danger
                        : AppColors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(width: 10),
              ],
              FilledButton(
                onPressed: saving ? null : onSave,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    else
                      Icon(FluentIcons.save, size: 13),
                    SizedBox(width: 7),
                    Text(saving ? 'Saving...' : 'Save review'),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _PlanCheckbox(this)),
              SizedBox(width: 16),
              Expanded(
                child: JournalComboField(
                  label: 'Which plan did you intend to follow?',
                  value: entryPlan,
                  items: plans,
                  onChanged: onEntryPlanChanged,
                  onAdd: onAddPlan,
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: JournalComboField(
                  label: 'Entry Confluences',
                  value: entryConfluence,
                  items: confluences,
                  onChanged: onEntryConfluenceChanged,
                  onAdd: onAddConfluence,
                ),
              ),
              SizedBox(width: 16),
              Expanded(child: _TradeManagementField(this)),
            ],
          ),
          SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _MistakesField(this)),
              SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: JournalComboField(
                        label: 'Entry emotion',
                        value: entryEmotion,
                        items: emotions,
                        onChanged: onEntryEmotionChanged,
                        onAdd: onAddEmotion,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: JournalComboField(
                        label: 'Exit Emotion',
                        value: exitEmotion,
                        items: emotions,
                        onChanged: onExitEmotionChanged,
                        onAdd: onAddEmotion,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          JournalSectionLabel('Add a note or voice reflection'),
          SizedBox(
            height: 170,
            child: TextBox(
              controller: reflectionController,
              maxLines: null,
              placeholder: 'Write your reflection here...',
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCheckbox extends StatelessWidget {
  final JournalReviewPanel panel;

  const _PlanCheckbox(this.panel);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalSectionLabel('Plan'),
        Row(
          children: [
            Checkbox(
              checked: panel.followedPlan,
              onChanged: (value) {
                if (value != null) {
                  panel.onFollowedPlanChanged(value);
                }
              },
            ),
            Expanded(child: Text('I followed my trade plan')),
          ],
        ),
      ],
    );
  }
}

class _TradeManagementField extends StatelessWidget {
  final JournalReviewPanel panel;

  const _TradeManagementField(this.panel);

  @override
  Widget build(BuildContext context) {
    return JournalFieldShell(
      label: 'Trade Management',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in panel.managementTags)
            JournalMiniTag(
              tag,
              selected: panel.selectedManagementTags.contains(tag),
              onPressed: () => panel.onToggleManagementTag(tag),
            ),
          _AddOptionChip(
            label: 'Add',
            title: 'Add trade management',
            onAdd: panel.onAddManagementTag,
          ),
        ],
      ),
    );
  }
}

class _MistakesField extends StatelessWidget {
  final JournalReviewPanel panel;

  const _MistakesField(this.panel);

  @override
  Widget build(BuildContext context) {
    return JournalFieldShell(
      label: 'Mistakes',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final mistake in panel.mistakeTags)
            JournalMiniTag(
              mistake,
              selected: panel.selectedMistakes.contains(mistake),
              removable: panel.selectedMistakes.contains(mistake),
              onPressed: () => panel.onToggleMistake(mistake),
            ),
          _AddOptionChip(
            label: 'Add',
            title: 'Add mistake',
            onAdd: panel.onAddMistake,
          ),
        ],
      ),
    );
  }
}

class _AddOptionChip extends StatelessWidget {
  final String label;
  final String title;
  final ValueChanged<String> onAdd;

  const _AddOptionChip({
    required this.label,
    required this.title,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: () => _showAddOptionDialog(context),
      style: ButtonStyle(
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.add, size: 11, color: AppColors.primary),
          SizedBox(width: 5),
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
          constraints: BoxConstraints(maxWidth: 360),
          title: Text(title, style: TextStyle(fontSize: 18)),
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
