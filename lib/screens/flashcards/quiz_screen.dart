import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../services/study_ai.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/answer_match.dart';
import '../../utils/format.dart';
import '../actions.dart';

/// A quiz on a set, one question at a time: multiple choice, true or
/// false, fill in the blank and typed answers. After each answer the right
/// one and an explanation show; the score comes at the end. Right answers
/// count like "Got It" and wrong ones like "Again" for smart review.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.setId, required this.questions});

  final String setId;
  final List<QuizQuestion> questions;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

/// One answered question, for the result card and the summary.
class _Answered {
  const _Answered(this.question, this.given, this.verdict, this.feedback);

  final QuizQuestion question;
  final String given;
  final AnswerVerdict verdict;
  final String feedback;
}

const _green = Color(0xFF2E9E6B);

class _QuizScreenState extends State<QuizScreen> {
  final _store = AppStore.instance;

  late List<QuizQuestion> _questions = List.of(widget.questions);
  int _index = 0;
  int? _picked;
  final _typed = TextEditingController();
  final _typedFocus = FocusNode();

  /// Waiting for the study server's verdict on a typed answer.
  bool _checking = false;
  _Answered? _result;
  final List<_Answered> _answers = [];

  @override
  void dispose() {
    _typed.dispose();
    _typedFocus.dispose();
    super.dispose();
  }

  bool get _finished => _index >= _questions.length;
  QuizQuestion get _question => _questions[_index];
  int get _correct =>
      _answers.where((a) => a.verdict == AnswerVerdict.correct).length;

  bool get _canCheck =>
      _question.isChoice ? _picked != null : _typed.text.trim().isNotEmpty;

  Future<void> _check() async {
    if (!_canCheck || _checking || _result != null) return;
    final q = _question;
    final String given;
    AnswerVerdict verdict;
    var feedback = q.explanation;

    if (q.isChoice) {
      given = q.options[_picked!];
      verdict = _picked == q.answerIndex
          ? AnswerVerdict.correct
          : AnswerVerdict.wrong;
    } else {
      given = _typed.text.trim();
      verdict = judgeAnswer(given, q.answer, acceptable: q.acceptable);
      // The study server judges by meaning; the phone's check stands if it
      // can't be reached.
      if (verdict != AnswerVerdict.correct && StudyAi.isOn) {
        setState(() => _checking = true);
        try {
          final check = await StudyAi.checkAnswer(
            question: q.prompt,
            answer: q.answer,
            acceptable: q.acceptable,
            userAnswer: given,
          );
          verdict = check.correct
              ? AnswerVerdict.correct
              : check.partly
                  ? AnswerVerdict.partly
                  : AnswerVerdict.wrong;
          if (check.feedback.isNotEmpty) feedback = check.feedback;
        } on StudyAiException catch (e) {
          debugPrint('Answer check unavailable: ${e.code}');
        }
        if (!mounted) return;
        _checking = false;
      }
    }

    final answered = _Answered(q, given, verdict, feedback);
    _answers.add(answered);
    _store.recordCardsReviewed(1);
    if (q.cardId case final id?) {
      _store.scheduleCard(widget.setId, id,
          knewIt: verdict == AnswerVerdict.correct);
    }
    setState(() => _result = answered);
  }

  void _next() {
    setState(() {
      _index++;
      _picked = null;
      _typed.clear();
      _result = null;
    });
    if (_finished) {
      _store.markSetStudied(widget.setId,
          known: _correct, seen: _answers.length);
    } else if (!_question.isChoice) {
      _typedFocus.requestFocus();
    }
  }

  void _restart(List<QuizQuestion> questions) {
    setState(() {
      _questions = questions;
      _index = 0;
      _picked = null;
      _typed.clear();
      _result = null;
      _answers.clear();
    });
  }

  Future<void> _newQuiz() async {
    final deck = _store.setById(widget.setId);
    if (deck == null) return;
    final made = await makeQuiz(context, deck);
    if (made == null || !mounted) return;
    _restart(made);
  }

  @override
  Widget build(BuildContext context) {
    final deck = _store.setById(widget.setId);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        title: Text(
          deck == null ? 'Quiz' : 'Quiz · ${deck.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: kHeadingFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: _questions.isEmpty
            ? const Center(child: Text('This quiz has no questions.'))
            : _finished
                ? _Summary(
                    answers: _answers,
                    onRetry: () =>
                        _restart(List.of(_questions)..shuffle(math.Random())),
                    onNewQuiz: _newQuiz,
                    onDone: () => Navigator.of(context).pop(),
                  )
                : _buildQuestion(),
      ),
    );
  }

  Widget _buildQuestion() {
    final q = _question;
    final result = _result;
    final last = _index + 1 == _questions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Question ${_index + 1} of ${_questions.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.statLabel),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(q.type.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.statLabel),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _index / _questions.length,
              minHeight: 5,
              color: AppColors.primary,
              backgroundColor: AppColors.primarySoft,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  q.prompt,
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (q.isChoice)
                for (var i = 0; i < q.options.length; i++)
                  _OptionTile(
                    text: q.options[i],
                    state: _optionState(i),
                    onTap: result == null ? () => setState(() => _picked = i) : null,
                  )
              else
                TextField(
                  controller: _typed,
                  focusNode: _typedFocus,
                  autofocus: true,
                  enabled: result == null && !_checking,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _check(),
                  decoration: InputDecoration(
                    labelText: q.type == QuestionType.fillBlank
                        ? 'The missing word or phrase'
                        : 'Your answer',
                    border: const OutlineInputBorder(),
                  ),
                ),
              if (result != null) ...[
                const SizedBox(height: 16),
                _ResultCard(result),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: result == null
                  ? (_canCheck && !_checking ? _check : null)
                  : _next,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onFill,
                disabledBackgroundColor: AppColors.primarySoft,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.onFill),
                    )
                  : Text(
                      result == null
                          ? 'Check'
                          : last
                              ? 'See Results'
                              : 'Next',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  _OptionState _optionState(int i) {
    final result = _result;
    if (result == null) {
      return _picked == i ? _OptionState.picked : _OptionState.idle;
    }
    if (i == _question.answerIndex) return _OptionState.right;
    if (i == _picked) return _OptionState.wrong;
    return _OptionState.dim;
  }
}

enum _OptionState { idle, picked, right, wrong, dim }

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.text, required this.state, this.onTap});

  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (Color border, Color fill, IconData? icon) = switch (state) {
      _OptionState.idle => (AppColors.border, AppColors.surface, null),
      _OptionState.picked => (AppColors.primary, AppColors.primarySoft, null),
      _OptionState.right => (
          _green,
          _green.withValues(alpha: 0.12),
          AppIcons.done
        ),
      _OptionState.wrong => (
          AppColors.streakRed,
          AppColors.streakRed.withValues(alpha: 0.1),
          AppIcons.close
        ),
      _OptionState.dim => (AppColors.border, AppColors.surface, null),
    };
    final dim = state == _OptionState.dim;

    return Semantics(
      button: onTap != null,
      selected: state == _OptionState.picked,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: border, width: state == _OptionState.idle ? 1 : 2),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: dim ? AppColors.textMuted : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (icon != null) ...[
                    const SizedBox(width: 10),
                    Icon(icon, size: 20, color: border),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard(this.answered);

  final _Answered answered;

  @override
  Widget build(BuildContext context) {
    final verdict = answered.verdict;
    final (String headline, Color color, IconData icon) = switch (verdict) {
      AnswerVerdict.correct => ('Correct!', _green, AppIcons.done),
      AnswerVerdict.partly => ('Partly right', AppColors.primaryDeep, AppIcons.suggest),
      AnswerVerdict.wrong => ('Not quite', AppColors.streakRed, AppIcons.close),
    };
    final q = answered.question;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(headline,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          if (verdict != AnswerVerdict.correct) ...[
            const SizedBox(height: 8),
            Text('Right answer: ${q.answer}',
                style: AppText.itemTitle.copyWith(height: 1.4)),
          ],
          if (answered.feedback.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(answered.feedback,
                style: AppText.statLabel.copyWith(height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.answers,
    required this.onRetry,
    required this.onNewQuiz,
    required this.onDone,
  });

  final List<_Answered> answers;
  final VoidCallback onRetry;
  final VoidCallback onNewQuiz;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final correct =
        answers.where((a) => a.verdict == AnswerVerdict.correct).length;
    final missed = [
      for (final a in answers)
        if (a.verdict != AnswerVerdict.correct) a,
    ];
    final percent = answers.isEmpty ? 0 : (correct * 100 / answers.length).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        Icon(AppIcons.trophy, size: 56, color: AppColors.primaryDeep),
        const SizedBox(height: 14),
        Text(
          '$percent%',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: kHeadingFont,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'You got $correct of ${plural(answers.length, 'question')} right.',
          textAlign: TextAlign.center,
          style: AppText.statLabel.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onFill,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Try Again (Shuffled)',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: onNewQuiz,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: BorderSide(color: AppColors.border, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('New Quiz',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        Center(child: TextButton(onPressed: onDone, child: const Text('Done'))),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('To look at again', style: AppText.sectionTitle),
          const SizedBox(height: 8),
          for (final a in missed)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.question.prompt.split('\n').first,
                      style: AppText.itemTitle.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('You: ${a.given}', style: AppText.statLabel),
                  Text('Right: ${a.question.answer}',
                      style: AppText.statLabel.copyWith(color: AppColors.primaryDeep)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
