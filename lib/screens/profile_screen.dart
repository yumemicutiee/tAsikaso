import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';
import 'actions.dart';
import 'analysis_screen.dart';
import 'help_screen.dart';
import 'plans_screen.dart';

/// Profile: study stats and app settings.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.instance;

    return Column(
      children: [
        AppHeader(title: 'Profile', onSettings: () => openSettings(context)),
        Expanded(
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final name = store.prefs.userName.trim();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primarySoft,
                      child: name.isEmpty
                          ? Icon(AppIcons.avatar,
                              size: 40, color: AppColors.primaryDeep)
                          : Text(
                              name.characters.first.toUpperCase(),
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primaryDeep,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => _editName(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name.isEmpty ? 'Add Your Name' : name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: kHeadingFont,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(AppIcons.edit,
                              size: 16, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _StatBox(
                          value: '${store.streakDays}',
                          label: 'Day Streak',
                          color: AppColors.streakText),
                      const SizedBox(width: 12),
                      _StatBox(
                          value: '${store.notes.length}',
                          label: 'Notes',
                          color: AppColors.primaryDeep),
                      const SizedBox(width: 12),
                      _StatBox(
                          value: '${store.sets.length}',
                          label: 'Card Sets',
                          color: AppColors.primaryDeep),
                    ],
                  ),
                  const SizedBox(height: 24),
                  PlusHero(
                    title: kPlusName,
                    subtitle: 'Suggested cards, full analysis history and backup.',
                    action: SizedBox(
                      height: 34,
                      child: FilledButton(
                        onPressed: () => openPlans(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.onFill,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('See Plans',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Group(children: [
                    _row(AppIcons.chart, 'Pomodoro Analysis',
                        () => openAnalysis(context)),
                    _row(AppIcons.settings, 'Settings',
                        () => openSettings(context)),
                    _row(AppIcons.notifications, 'Notifications & Reminders',
                        () => openSettings(context)),
                    _row(AppIcons.backup, 'Backup & Sync',
                        () => openPlans(context),
                        badge: 'Plus'),
                  ]),
                  const SizedBox(height: 16),
                  _Group(children: [
                    _row(AppIcons.help, 'Help & FAQ', () => openHelp(context)),
                  ]),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static Future<void> _editName(BuildContext context) async {
    final store = AppStore.instance;
    final name = await showTextInputDialog(
      context,
      title: 'Your Name',
      initial: store.prefs.userName,
      hint: 'Shown in greetings',
    );
    if (name == null) return;
    store.updatePrefs(store.prefs.copyWith(userName: name.trim()));
  }

  static Widget _row(IconData icon, String label, VoidCallback onTap,
          {String? badge}) =>
      ListTile(
        leading: Icon(icon, color: AppColors.ink, size: 22),
        title: Row(
          children: [
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.itemTitle),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    )),
              ),
            ],
          ],
        ),
        trailing: Icon(AppIcons.chevronRight,
            color: AppColors.textMuted, size: 18),
        dense: true,
        onTap: onTap,
      );
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(value, style: AppText.statValue.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(label, style: AppText.itemMeta),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 16, endIndent: 16),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
