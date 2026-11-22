import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';
import '../widgets/app_logo.dart';
import 'actions.dart';
import 'capture/pdf_import.dart' show kPdfImportPageLimit;

Future<void> openHelp(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
    );

/// Where Smart Study sends what, said the same way in Help and Settings.
const kSmartStudyPrivacy = 'Only text leaves the phone, never your photos: '
    'the text read from them, your cards and your typed quiz answers go to '
    'your study server and on to Anthropic.';

/// Short answers to the questions students ask most.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = <(String, String)>[
    (
      'How do I scan my notes?',
      'Tap the camera button in the middle of the bottom bar. On Android the '
          "Smart Scanner finds the page edges for you; the app's own camera "
          'finds them too (see below), and you can drag the four corners if '
          "they're off. "
          'Scan several pages and tap Next: their text is read on your '
          'phone while you watch. Then save them as Text Notes (the text, to '
          'edit and turn into flashcards) or as Flashcards to write while '
          'looking at your photos.',
    ),
    (
      'How does the app find the page edges?',
      "The app's own camera and gallery import use AI models that run on "
          'your phone (no internet, and your photos stay on it), so they work '
          'the same on every phone, with or without Google services, and in '
          "the browser. If the corners aren't right, drag them. The models "
          'are DocAligner by Ze Yuan (DocsaidLab), github.com/DocsaidLab/'
          'DocAligner.',
    ),
    (
      'Can the app read the text in my photos?',
      'Yes, on phones. When you save, the text is read on your phone (no '
          'internet needed). Save as Text Notes and the note opens on its '
          'text: tap Edit to fix a misread word, and Make Flashcards to turn '
          'it into cards. Your photos stay one tap away. Without Smart Study, '
          'cards are suggested from lines like "Term: definition" for you to '
          'add or skip.',
    ),
    (
      'Where are my notes, and where do my flashcards go?',
      'When you save notes you pick a folder (or make one), and they go in '
          "that folder's Notebook: open the folder, then Notebook. When you "
          'tap Make Flashcards on a note you pick where the cards go: a new '
          'set in any folder, or a set you already have.',
    ),
    (
      'Can I turn a PDF into notes or flashcards?',
      'Yes. Tap + and choose Import PDF (or the PDF button on the camera '
          'screen), then save it as Text Notes, a PDF or flashcards. Lecture '
          'slides and handouts work everywhere; scanned PDFs are read on '
          'Android and iOS. The first $kPdfImportPageLimit pages are read. '
          'To add cards to a set you already have, open the set and choose '
          'Make Cards from a PDF.',
    ),
    (
      'What is Smart Study?',
      'With a study server set up in Settings → Smart Study, Claude (an AI '
          'by Anthropic) types up your notes and writes a summary, key '
          'concepts, flashcards and quizzes. $kSmartStudyPrivacy It needs '
          'internet; without it, scanning, cards and quizzes still work on '
          'the phone.',
    ),
    (
      'How do quizzes work?',
      'Any set with two or more cards has Take a Quiz: multiple choice, '
          'true or false, fill in the blank and typed answers. New Quiz lets '
          'you pick how many questions and which types. Typed answers forgive '
          'spelling slips; with Smart Study on they are judged by meaning. A '
          'partly right answer counts as half.',
    ),
    (
      'How does the Pomodoro timer work?',
      'Focus for one Pomodoro (25 minutes by default), then take a short '
          'break. After every few Pomodoros you get a long break. Finished '
          'Pomodoros count toward the current task and your daily goal. You '
          'can change all the lengths in Settings.',
    ),
    (
      'What is Focus Mode?',
      'Pressing START opens a full-screen timer with nothing else on it. '
          'Close it with the ✕ to pause the timer, then press RESUME to carry on.',
    ),
    (
      'How is my streak counted?',
      'Each day you finish a Pomodoro or review flashcards adds a day. Miss '
          'a whole day and the streak starts again.',
    ),
    (
      'What happens when a Pomodoro or break ends?',
      'Settings → When Time Is Up: Alarm Clock (your phone\'s alarm sound), '
          'Vibration Only, Alarm Clock and Vibration, or Off. The alarm '
          'rings on the alarm volume, so it works even when the phone is on '
          'silent, and keeps ringing until you tap the alert, for up to a '
          'minute. It sounds even when the app is closed.',
    ),
    (
      "Why didn't I get a notification?",
      'Check that When Time Is Up isn\'t Off in Settings and that notifications are '
          "allowed for the app in your phone's settings. Some phones delay "
          'alerts to save battery; allowing "Alarms & reminders" for the app '
          'makes them exact.',
    ),
    (
      'How does Smart Review work?',
      'Each flashcard comes back when you are about to forget it. A card '
          'you know comes back after a growing gap (1, 3, 7, 14 days and '
          'so on); a card you miss comes back tomorrow. A set shows how '
          'many cards are due today, and you can always study all of them.',
    ),
    (
      'What does tAsikaso+ add, and can I try it?',
      'tAsikaso+ adds every week, month and year in Pomodoro Analysis with '
          'the heatmap and full timeline, smart review, app colors, Google '
          'Drive sync and backup files, and unlimited suggested cards (the '
          'free plan gets 20 a month). While payments are being set up, '
          'every plan is free to try: open Profile → See Plans, pick Monthly, '
          'Semester or Yearly, switch whenever you like, or tap Go Back to '
          'Free Plan. Nothing is deleted when a plan ends.',
    ),
    (
      'Where is my data saved?',
      'Everything is saved on this phone; deleting the app deletes it. To '
          'keep a copy, open Profile → Backup & Sync: sync to your Google '
          'Drive, or tap Back Up Now for a backup file (both tAsikaso+). '
          'Restoring on any phone from the same screen is free. Your study '
          "server's app token is never in a backup.",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: subPageAppBar('Help & FAQ'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          for (final (q, a) in _faq)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              // Material, not a coloured box: the tap ripple is drawn on it,
              // and a box on top would hide it.
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Theme(
                  // No divider lines above and below an open answer.
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(q, style: AppText.itemTitle),
                    iconColor: AppColors.primaryDeep,
                    collapsedIconColor: AppColors.textSecondary,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    expandedAlignment: Alignment.topLeft,
                    children: [
                      Text(a,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: () => openPrivacyPolicy(context),
              child: const Text('Privacy Policy'),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: kAppName,
                applicationVersion: kAppVersion,
                applicationIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: AppLogo(size: 64),
                ),
              ),
              child: const Text('Open-Source Licenses'),
            ),
          ),
        ],
      ),
    );
  }
}
