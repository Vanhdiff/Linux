import 'package:fluent_ui/fluent_ui.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/app_panel.dart';
import 'journal_review_fields.dart';
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
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
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
                const SizedBox(width: 10),
              ],
              FilledButton(
                onPressed: saving ? null : onSave,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (saving)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    else
                      const Icon(FluentIcons.save, size: 13),
                    const SizedBox(width: 7),
                    Text(saving ? 'Saving...' : 'Save review'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: JournalPlanCheckbox(
                  followedPlan: followedPlan,
                  onChanged: onFollowedPlanChanged,
                ),
              ),
              const SizedBox(width: 16),
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
          const SizedBox(height: 14),
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
              const SizedBox(width: 16),
              Expanded(
                child: JournalTagSelectorField(
                  label: 'Trade Management',
                  tags: managementTags,
                  selectedTags: selectedManagementTags,
                  onToggleTag: onToggleManagementTag,
                  addTitle: 'Add trade management',
                  onAddTag: onAddManagementTag,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: JournalTagSelectorField(
                  label: 'Mistakes',
                  tags: mistakeTags,
                  selectedTags: selectedMistakes,
                  onToggleTag: onToggleMistake,
                  addTitle: 'Add mistake',
                  onAddTag: onAddMistake,
                  removableWhenSelected: true,
                ),
              ),
              const SizedBox(width: 16),
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
                    const SizedBox(width: 12),
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
          const SizedBox(height: 14),
          const JournalSectionLabel('Add a note or voice reflection'),
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
