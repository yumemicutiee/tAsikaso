import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';

Future<void> openHelp(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
    );

/// Short answers to the questions students ask most.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = <(String, String)>[
    (
      'How do I scan my notes?',
      'Tap the camera button in the middle of the bottom bar. On Android the '
          'Smart Scanner finds the page edges for you; otherwise take a photo '
          'and drag the four corners to crop. You can scan several pages, '
          'then save them as a PDF or as flashcards.',
    ),
    (
      'Can the app read the text in my photos?',
      'Yes, on phones. When you save, the text is read on your phone (no '
          'internet needed). Notes become searchable, you can open "View '
          'Text" to copy it, and flashcards get suggested cards to add.',
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
      "Why didn't I get a notification?",
      'Check that Timer Alerts is on in Settings and that notifications are '
          "allowed for the app in your phone's settings. Some phones delay "
          'alerts to save battery; allowing "Alarms & reminders" for the app '
          'makes them exact.',
    ),
    (
      'Where is my data saved?',
      'Everything is saved on this phone. Deleting the app deletes your '
          'data. Backup & sync across devices is coming with tAsikaso+.',
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
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
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
        ],
      ),
    );
  }
}
