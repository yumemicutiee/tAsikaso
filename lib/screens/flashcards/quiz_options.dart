import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';

/// What the user picked for a new quiz: how many questions, of which types.
typedef QuizOptions = ({int count, Set<QuestionType> types});

/// The quiz sizes offered.
const quizSizes = [5, 10, 15, 20];

/// The sizes that make sense for a set of [cardCount] cards: a quiz made
/// from the cards asks about each card once, the study server about twice
/// as many ([withAi]). The largest is the most there can be.
List<int> quizSizesFor(int cardCount, {required bool withAi}) {
  final most = withAi ? cardCount * 2 : cardCount;
  final sizes = [for (final n in quizSizes) if (n < most) n];
  if (most > 0 && (sizes.isEmpty || sizes.last < quizSizes.last)) {
    sizes.add(most < quizSizes.last ? most : quizSizes.last);
  }
  return sizes;
}

/// Asks how many questions and which types for a new quiz on a set of
/// [cardCount] cards. Null if the user backed out.
Future<QuizOptions?> showQuizOptions(
  BuildContext context, {
  required int cardCount,
  required bool withAi,
}) {
  return showModalBottomSheet<QuizOptions>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _QuizOptionsSheet(
      cardCount: cardCount,
      sizes: quizSizesFor(cardCount, withAi: withAi),
    ),
  );
}

class _QuizOptionsSheet extends StatefulWidget {
  const _QuizOptionsSheet({required this.cardCount, required this.sizes});

  final int cardCount;
  final List<int> sizes;

  @override
  State<_QuizOptionsSheet> createState() => _QuizOptionsSheetState();
}

class _QuizOptionsSheetState extends State<_QuizOptionsSheet> {
  /// 10 when it's offered, otherwise the largest size up to 10.
  late int _count = widget.sizes.lastWhere((n) => n <= 10,
      orElse: () => widget.sizes.isEmpty ? 10 : widget.sizes.first);
  final Set<QuestionType> _types = {...QuestionType.values};

  void _toggle(QuestionType type) {
    setState(() {
      if (_types.contains(type)) {
        // At least one type stays on.
        if (_types.length > 1) _types.remove(type);
      } else {
        _types.add(type);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetTitle('New Quiz',
                subtitle: 'From ${plural(widget.cardCount, 'card')}'),
            const SizedBox(height: 16),
            Text('Questions', style: AppText.itemMeta),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in widget.sizes)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: n == _count,
                    showCheckmark: false,
                    selectedColor: AppColors.primarySoft,
                    side: BorderSide(
                        color: n == _count
                            ? AppColors.primary
                            : AppColors.border),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                    onSelected: (_) => setState(() => _count = n),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Question Types', style: AppText.itemMeta),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in QuestionType.values)
                  FilterChip(
                    label: Text(t.label),
                    selected: _types.contains(t),
                    selectedColor: AppColors.primarySoft,
                    checkmarkColor: AppColors.primaryDeep,
                    side: BorderSide(
                        color: _types.contains(t)
                            ? AppColors.primary
                            : AppColors.border),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    onSelected: (_) => _toggle(t),
                  ),
              ],
            ),
            if (_types.length == 1) ...[
              const SizedBox(height: 6),
              Text('At least one type stays on.', style: AppText.itemMeta),
            ],
            const SizedBox(height: 20),
            AccentButton(
              label: 'Make Quiz',
              onPressed: () => Navigator.of(context)
                  .pop((count: _count, types: Set.of(_types))),
            ),
          ],
        ),
      ),
    );
  }
}
