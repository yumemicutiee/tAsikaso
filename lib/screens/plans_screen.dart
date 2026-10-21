import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../data/plans.dart';
import '../models/models.dart' show Subscription;
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';

Future<void> openPlans(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
    );

/// Tells a free account that [feature] is part of tAsikaso+, with a way to
/// the plans page. Returns once the sheet (and the plans page, if opened)
/// is closed.
Future<void> showPlusPrompt(BuildContext context, PlusFeature feature) async {
  final open = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: PlusHero.gradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(AppIcons.plus, size: 18, color: AppColors.gold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(feature.title,
                      style: TextStyle(
                        fontFamily: kHeadingFont,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('${feature.description} Part of $kPlusName.',
                style: AppText.statLabel.copyWith(fontSize: 13, height: 1.45)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onFill,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('See Plans',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not Now'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (open == true && context.mounted) await openPlans(context);
}

/// One line of the Free vs Plus comparison. [soon] marks a Plus feature
/// that's still being built.
typedef PlanFeature = ({
  String name,
  bool free,
  String? freeNote,
  bool soon,
});

/// What each plan includes. Everything you need to study stays free: the
/// timer, tasks, scanning to PDF, your own flashcards, quizzes and this
/// week's analysis. tAsikaso+ adds extras and the features that cost money
/// to run (cloud backup, unlimited suggested cards).
const List<PlanFeature> planFeatures = [
  (name: 'Pomodoro timer, presets & unlimited tasks', free: true, freeNote: null, soon: false),
  (name: 'Focus Mode with moving bubbles', free: true, freeNote: null, soon: false),
  (name: 'Scan notes to PDF (auto-crop, no watermark)', free: true, freeNote: null, soon: false),
  (name: 'Flashcards you write yourself, and quizzes', free: true, freeNote: null, soon: false),
  (name: 'Search & copy the text in your notes', free: true, freeNote: null, soon: false),
  (name: 'Light & dark mode, reminders, timer alerts', free: true, freeNote: null, soon: false),
  (name: 'Restore a backup you already have', free: true, freeNote: null, soon: false),
  (name: 'Pomodoro Analysis', free: true, freeNote: 'This week', soon: false),
  (name: 'Suggested cards from your notes', free: true, freeNote: '$kFreeSuggestedCardsPerMonth / month', soon: false),
  (name: 'Month & year analysis, heatmap, full timeline', free: false, freeNote: null, soon: false),
  (name: 'App colors & your own color', free: false, freeNote: null, soon: false),
  (name: 'Smart review (spaced repetition)', free: false, freeNote: null, soon: false),
  (name: 'Google Drive sync & backup files', free: false, freeNote: null, soon: false),
];

/// tAsikaso+: what it includes, the plans, and (while payments aren't
/// connected) a free test checkout: start any plan, switch, or go back to
/// Free.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _store = AppStore.instance;
  late PlusPlan _picked = _store.plan ?? PlusPlan.yearly;

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), showCloseIcon: true));
  }

  void _start() {
    if (!kTestPurchases) {
      _toast('Payments for $kPlusName are coming soon. Thanks for your '
          'interest!');
      return;
    }
    final switching = _store.isPlus;
    _store.startPlan(_picked);
    final ends = formatNoteDate(_store.subscription!.endsAt!);
    _toast(switching
        ? 'Switched to $kPlusName ${_picked.title}, until $ends.'
        : 'Welcome to $kPlusName ${_picked.title}! Active until $ends.');
  }

  Future<void> _downgrade() async {
    final plan = _store.plan;
    if (plan == null) return;
    final sure = await showConfirmDialog(
      context,
      title: 'Go Back to Free?',
      message: 'Your ${plan.title} plan ends now. Nothing is deleted: '
          'colors go back to Navy, analysis shows this week, smart review '
          'and Google Drive sync pause, and suggested cards are '
          '$kFreeSuggestedCardsPerMonth a month again. Start a plan again '
          'anytime to get it all back.',
      confirmLabel: 'Go to Free',
    );
    if (!sure || !mounted) return;
    _store.endPlan();
    _toast("You're on the free plan now.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subPageAppBar(kPlusName),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) {
          final current = _store.plan;
          final sub = _store.subscription;
          final pickedIsCurrent = current == _picked;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              if (current != null && sub != null)
                _CurrentPlan(plan: current, subscription: sub)
              else
                const PlusHero(
                  title: 'Study smarter with $kPlusName',
                  subtitle: 'Cards made from your notes, your full focus '
                      'history, and backup for everything.',
                ),
              if (kTestPurchases) ...[
                const SizedBox(height: 12),
                const _TestModeNote(),
              ],
              const SizedBox(height: 20),
              const _Comparison(),
              const SizedBox(height: 20),
              Text(current == null ? 'Choose a Plan' : 'Change Plan',
                  style: AppText.sectionTitle),
              const SizedBox(height: 10),
              for (final plan in PlusPlan.values) ...[
                if (plan != PlusPlan.values.first) const SizedBox(height: 10),
                _PriceOption(
                  title: plan.title,
                  price: '${plan.price} / ${plan.per}',
                  note: plan.note,
                  badge: plan == current ? 'Current' : plan.badge,
                  selected: _picked == plan,
                  onTap: () => setState(() => _picked = plan),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: pickedIsCurrent ? null : _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onFill,
                    disabledBackgroundColor: AppColors.primarySoft,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    pickedIsCurrent
                        ? 'This Is Your Plan'
                        : current != null
                            ? 'Switch to ${_picked.title}'
                            : kTestPurchases
                                ? 'Start ${_picked.title} Plan'
                                : 'Start 7-Day Free Trial',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                kTestPurchases
                    ? 'No payment is taken. ${_picked.title} runs until '
                        '${formatNoteDate(_picked.endFrom(clock.now()))}; '
                        'switch plans or go back to Free anytime.'
                    : 'Free for 7 days, then ${_picked.price} every '
                        '${_picked.per}. Cancel anytime in Google Play.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              if (current != null) ...[
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: _downgrade,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.streakRed),
                    child: const Text('Go Back to Free Plan'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// "You're on tAsikaso+ Yearly · until Oct 21, 2027".
class _CurrentPlan extends StatelessWidget {
  const _CurrentPlan({required this.plan, required this.subscription});

  final PlusPlan plan;
  final Subscription subscription;

  @override
  Widget build(BuildContext context) {
    final end = subscription.endsAt;
    final daysLeft = end == null
        ? null
        : (end.difference(clock.now()).inHours / 24).ceil();
    return PlusHero(
      title: "You're on $kPlusName ${plan.title}",
      subtitle: [
        'Started ${formatNoteDate(subscription.startedAt)}',
        if (end != null)
          'active until ${formatNoteDate(end)}'
              '${daysLeft != null && daysLeft <= 31 ? ' (${plural(daysLeft, 'day')} left)' : ''}',
        if (subscription.test) 'test plan, no charge',
      ].join(' · '),
    );
  }
}

/// Says plainly that plans cost nothing while payments aren't connected.
class _TestModeNote extends StatelessWidget {
  const _TestModeNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.goldSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // goldSoft is a dark brown in dark mode, so the text follows ink.
          Icon(AppIcons.suggest, size: 16, color: AppColors.ink),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Test mode: payments aren’t connected yet, so every plan is '
              'free to try. Start one, switch between Monthly, Semester and '
              'Yearly, or go back to Free whenever you like.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deep-sky card with a crown, used on the Dashboard banner and Plans page.
class PlusHero extends StatelessWidget {
  const PlusHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
    this.onClose,
  });

  final String title;
  final String subtitle;

  /// Optional button under the text (e.g. "See Plans").
  final Widget? action;

  /// Shows a small × in the corner when set.
  final VoidCallback? onClose;

  /// The hero background for the current [Palette].
  static LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.heroTop, AppColors.heroBottom],
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          // Soft decorative circles.
          const Positioned(
            right: -30,
            top: -30,
            child: PlusBlob(size: 120, alpha: 0.08),
          ),
          const Positioned(
            right: 40,
            bottom: -40,
            child: PlusBlob(size: 90, alpha: 0.06),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(AppIcons.plus, color: AppColors.gold, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(right: onClose == null ? 0 : 20),
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontFamily: kHeadingFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: 12),
                        action!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            Positioned(
              right: 2,
              top: 2,
              child: IconButton(
                tooltip: 'Hide',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                icon: Icon(AppIcons.close,
                    size: 16, color: Colors.white.withValues(alpha: 0.8)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A soft see-through circle for the navy tAsikaso+ backgrounds.
class PlusBlob extends StatelessWidget {
  const PlusBlob({super.key, required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison();

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('Features', style: head)),
              SizedBox(width: 64, child: Center(child: Text('Free', style: head))),
              SizedBox(width: 44, child: Center(child: Text('Plus', style: head))),
            ],
          ),
          const SizedBox(height: 4),
          for (final f in planFeatures) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: f.name),
                        if (f.soon)
                          TextSpan(
                            text: '  Soon',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDeep,
                            ),
                          ),
                      ]),
                      style: TextStyle(fontSize: 12.5, color: AppColors.ink),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Center(
                      child: f.freeNote != null
                          ? Text(f.freeNote!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary))
                          : Icon(
                              f.free ? AppIcons.included : AppIcons.locked,
                              size: 17,
                              color: f.free
                                  ? AppColors.primaryDeep
                                  : AppColors.textMuted,
                            ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Center(
                      child: Icon(AppIcons.included,
                          size: 17, color: AppColors.primaryDeep),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceOption extends StatelessWidget {
  const _PriceOption({
    required this.title,
    required this.price,
    required this.note,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String price;
  final String note;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.primarySoft : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(
                  selected ? AppIcons.included : AppIcons.done,
                  size: 20,
                  color: selected ? AppColors.primaryDeep : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.sectionTitle),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            // Flexible so a long price can't push it off the row.
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.goldSoft,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(badge!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(note, style: AppText.statLabel),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(price,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
