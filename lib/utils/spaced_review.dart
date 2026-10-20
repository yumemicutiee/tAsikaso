/// Smart review (spaced repetition): how soon a card comes back.
///
/// A card you know comes back after a growing gap; one you miss comes back
/// tomorrow and the gap starts over. The first answer in a round is the one
/// that counts.
library;

/// Days until the next review, step by step, for cards answered "Got It".
const List<int> reviewSteps = [1, 3, 7, 14, 30, 60, 120, 180];

/// The gap (in days) after this answer, given the card's current gap.
int nextInterval(int interval, {required bool knewIt}) {
  if (!knewIt) return 1;
  for (final step in reviewSteps) {
    if (step > interval) return step;
  }
  return reviewSteps.last;
}
