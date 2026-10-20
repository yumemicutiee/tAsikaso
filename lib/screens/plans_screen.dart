import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';

Future<void> openPlans(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PlansScreen()),
    );

/// One line of the Free vs Plus comparison. [soon] marks a Plus feature
/// that's still being built.
typedef PlanFeature = ({
  String name,
  bool free,
  String? freeNote,
  bool soon,
});

/// What each plan includes. Everything you need to study stays free: the
/// timer, tasks, scanning to PDF, your own flashcards and this week's
/// analysis. tAsikaso+ adds extras and the features that cost money to run
/// (cloud backup).
const List<PlanFeature> planFeatures = [
  (name: 'Pomodoro timer, presets & unlimited tasks', free: true, freeNote: null, soon: false),
  (name: 'Focus Mode with moving bubbles', free: true, freeNote: null, soon: false),
  (name: 'Scan notes to PDF (auto-crop, no watermark)', free: true, freeNote: null, soon: false),
  (name: 'Flashcards you write yourself', free: true, freeNote: null, soon: false),
  (name: 'Search & copy the text in your notes', free: true, freeNote: null, soon: false),
  (name: 'Light & dark mode, reminders, timer alerts', free: true, freeNote: null, soon: false),
  (name: 'Pomodoro Analysis', free: true, freeNote: 'This week', soon: false),
  (name: 'Suggested cards from your notes', free: true, freeNote: '20 / month', soon: false),
  (name: 'Month & year analysis, heatmap, full timeline', free: false, freeNote: null, soon: false),
  (name: 'App colors & your own color', free: false, freeNote: null, soon: false),
  (name: 'Smart review (spaced repetition)', free: false, freeNote: null, soon: false),
  (name: 'Backup & restore (Google Drive or any file)', free: false, freeNote: null, soon: false),
];

/// Prices in Philippine pesos, set for students: the monthly plan costs less
/// than one fast-food meal, and the semester plan matches the school term.
enum _Plan {
  yearly('Yearly', '₱349', 'year', 'Just ₱29 a month', 'Save 41%'),
  semester('Semester', '₱199', '6 months', 'One school term', 'Save 32%'),
  monthly('Monthly', '₱49', 'month', 'Cancel anytime', null);

  const _Plan(this.title, this.price, this.per, this.note, this.badge);
  final String title;
  final String price;
  final String per;
  final String note;
  final String? badge;
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  _Plan _plan = _Plan.yearly;

  void _subscribe() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: Text('$kPlusName is coming soon. Thanks for your interest!'),
        showCloseIcon: true,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subPageAppBar(kPlusName),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          const PlusHero(
            title: 'Study smarter with $kPlusName',
            subtitle: 'Cards made from your notes, your full focus history, '
                'and backup for everything.',
          ),
          const SizedBox(height: 20),
          const _Comparison(),
          const SizedBox(height: 20),
          for (final plan in _Plan.values) ...[
            if (plan != _Plan.yearly) const SizedBox(height: 10),
            _PriceOption(
              title: plan.title,
              price: '${plan.price} / ${plan.per}',
              note: plan.note,
              badge: plan.badge,
              selected: _plan == plan,
              onTap: () => setState(() => _plan = plan),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _subscribe,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onFill,
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Start 7-Day Free Trial',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Free for 7 days, then ${_plan.price} every ${_plan.per}. '
            'Cancel anytime in Google Play.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          // Payments aren't connected yet: debug builds can switch Plus on
          // to try the Plus features. Never shown in release builds.
          if (kDebugMode)
            Center(
              child: TextButton(
                onPressed: _togglePlusForTesting,
                child: Text(AppStore.instance.isPlus
                    ? 'Turn Off Plus (testing)'
                    : 'Turn On Plus for Testing'),
              ),
            ),
        ],
      ),
    );
  }

  void _togglePlusForTesting() {
    final store = AppStore.instance;
    store.updatePrefs(store.prefs.copyWith(plus: !store.isPlus));
    setState(() {});
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
