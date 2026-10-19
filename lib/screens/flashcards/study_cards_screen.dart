import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';

/// Flip through a set: tap to see the answer, then "Again" (card comes back
/// later) or "Got It".
class StudyCardsScreen extends StatefulWidget {
  const StudyCardsScreen({super.key, required this.setId});

  final String setId;

  @override
  State<StudyCardsScreen> createState() => _StudyCardsScreenState();
}

class _StudyCardsScreenState extends State<StudyCardsScreen> {
  final _store = AppStore.instance;

  List<Flashcard> _queue = [];
  int _position = 0;
  bool _showBack = false;

  /// Cards answered "Got It" on the first try.
  final Set<String> _knewFirstTime = {};

  /// Cards answered at least once (counts toward "Reviewed" today).
  final Set<String> _seen = {};
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(shuffle: false);
  }

  void _load({required bool shuffle}) {
    final cards = List.of(_store.setById(widget.setId)?.cards ?? const <Flashcard>[]);
    if (shuffle) cards.shuffle(math.Random());
    _queue = cards;
    _total = cards.length;
    _position = 0;
    _showBack = false;
    _knewFirstTime.clear();
    _seen.clear();
  }

  void _restart({required bool shuffle}) => setState(() => _load(shuffle: shuffle));

  bool get _finished => _position >= _queue.length;

  void _answer({required bool knewIt}) {
    final card = _queue[_position];
    final firstTime = _seen.add(card.id);
    if (firstTime) _store.recordCardsReviewed(1);
    setState(() {
      if (knewIt) {
        if (firstTime) _knewFirstTime.add(card.id);
      } else {
        _queue.add(card); // see it again at the end
      }
      _position++;
      _showBack = false;
    });
    // Shown on the Dashboard under "Recent Flashcards".
    _store.markSetStudied(widget.setId,
        known: _knewFirstTime.length, seen: _seen.length);
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
          deck?.title ?? 'Flashcards',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: kHeadingFont,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Shuffle and Restart',
            onPressed: () => _restart(shuffle: true),
            icon: const Icon(AppIcons.again),
          ),
        ],
      ),
      body: SafeArea(
        child: _total == 0
            ? const Center(child: Text('This set has no cards yet.'))
            : _finished
                ? _Summary(
                    knew: _knewFirstTime.length,
                    total: _total,
                    onRestart: () => _restart(shuffle: true),
                    onDone: () => Navigator.of(context).pop(),
                  )
                : _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    final card = _queue[_position];
    final remaining = _queue.length - _position;
    final done = _seen.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              Text('$done of $_total seen', style: AppText.statLabel),
              const Spacer(),
              Text('${plural(remaining, 'card')} left', style: AppText.statLabel),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _total == 0 ? 0 : done / _total,
              minHeight: 5,
              color: AppColors.primary,
              backgroundColor: AppColors.primarySoft,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _showBack = !_showBack),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: _CardFace(
                  key: ValueKey('${card.id}-$_position-$_showBack'),
                  label: _showBack ? 'Answer' : 'Question',
                  text: _showBack ? card.back : card.front,
                  back: _showBack,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (!_showBack)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: () => setState(() => _showBack = true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onFill,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Show Answer',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => _answer(knewIt: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink,
                        side: BorderSide(color: AppColors.border, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(AppIcons.again, size: 18),
                      label: const Text('Again',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () => _answer(knewIt: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onFill,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(AppIcons.check, size: 18),
                      label: const Text('Got It',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CardFace extends StatelessWidget {
  const _CardFace({
    super.key,
    required this.label,
    required this.text,
    required this.back,
  });

  final String label;
  final String text;
  final bool back;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: back ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: back ? AppColors.primary : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: kHeadingFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          Text(
            back ? 'Tap to see the question' : 'Tap to flip',
            style: AppText.itemMeta,
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.knew,
    required this.total,
    required this.onRestart,
    required this.onDone,
  });

  final int knew;
  final int total;
  final VoidCallback onRestart;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.done, size: 56, color: AppColors.primaryDeep),
          const SizedBox(height: 16),
          Text(
            'Set complete!',
            style: TextStyle(
              fontFamily: kHeadingFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You knew $knew of ${plural(total, 'card')} on the first try.',
            textAlign: TextAlign.center,
            style: AppText.statLabel.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: onRestart,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onFill,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Study Again (Shuffled)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
