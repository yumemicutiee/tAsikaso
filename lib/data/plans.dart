/// tAsikaso+ plans, what they unlock, and the free tier's limits.
library;

/// Payments (Google Play Billing) aren't connected yet, so choosing a plan
/// switches it on without charging ("test purchases"): testers can try
/// every plan, switch between them and go back to Free. Build with
/// `--dart-define=TEST_PURCHASES=false` once real payments exist; the
/// plans page then stops handing out plans.
const bool kTestPurchases =
    bool.fromEnvironment('TEST_PURCHASES', defaultValue: true);

/// Suggested cards a free account gets each calendar month (cards the app
/// makes from notes, by the study server or from the text). Plus has no
/// limit.
const int kFreeSuggestedCardsPerMonth = 20;

/// The tAsikaso+ plans, in Philippine pesos, set for students.
enum PlusPlan {
  yearly('Yearly', '₱349', 'year', 12, 'Just ₱29 a month', 'Save 41%'),
  semester('Semester', '₱199', '6 months', 6, 'One school term', 'Save 32%'),
  monthly('Monthly', '₱49', 'month', 1, 'Cancel anytime', null);

  const PlusPlan(
      this.title, this.price, this.per, this.months, this.note, this.badge);

  final String title;
  final String price;
  final String per;

  /// How long one period of the plan lasts.
  final int months;
  final String note;
  final String? badge;

  /// When a period that starts at [start] ends (same day and time,
  /// [months] later; the 31st of a short month rolls into the next).
  DateTime endFrom(DateTime start) => DateTime(start.year,
      start.month + months, start.day, start.hour, start.minute, start.second);

  static PlusPlan? fromName(Object? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// What tAsikaso+ unlocks, with the words used when a free account taps
/// one of them.
enum PlusFeature {
  fullAnalysis(
    'Full Pomodoro Analysis',
    'See any week, month or year, step back through your history, and get '
        'the heatmap and the whole timeline. The free plan shows this week.',
  ),
  appColors(
    'App Colors',
    'Teal, Plum, Forest, Wine, Cocoa, Graphite, or any color you like, in '
        'light and dark.',
  ),
  smartReview(
    'Smart Review',
    'Each card comes back right before you would forget it, and every set '
        'shows how many cards are due today.',
  ),
  backup(
    'Backup & Sync',
    'Keep everything in your own Google Drive, synced by itself, or make a '
        'backup file. Restoring what you already saved stays free.',
  ),
  unlimitedSuggestions(
    'Unlimited Suggested Cards',
    'Get as many cards made from your notes as you like. The free plan '
        'includes $kFreeSuggestedCardsPerMonth a month.',
  );

  const PlusFeature(this.title, this.description);

  final String title;
  final String description;
}

/// `2026-10` for the month [d] is in; suggested cards are counted per month.
String monthKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}';
