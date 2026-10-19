import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../data/pomodoro_controller.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import 'actions.dart';
import 'capture/scan_flow.dart';
import 'dashboard_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'study_screen.dart';
import 'task_editor.dart';

/// Main scaffold: the four tabs, the bottom bar with the camera button, and
/// the floating "+" button.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  AppTab _tab = AppTab.dashboard;

  @override
  void initState() {
    super.initState();
    // The timer can finish on any screen (even in Focus Mode), so its
    // messages are shown from here. So are problems with saved data.
    final timer = PomodoroController.instance;
    timer.onMessage = _showMessage;
    AppStore.instance.problem.addListener(_showProblem);
    // Whatever happened while the app was starting, once the screen is up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final message = timer.takePendingMessage();
      if (message != null) _showMessage(message);
      _showProblem();
    });
  }

  @override
  void dispose() {
    if (PomodoroController.instance.onMessage == _showMessage) {
      PomodoroController.instance.onMessage = null;
    }
    AppStore.instance.problem.removeListener(_showProblem);
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
  }

  /// Data that couldn't be read or saved: the user must know, so it's a
  /// dialog, not a snack bar that's easy to miss.
  void _showProblem() {
    final store = AppStore.instance;
    final problem = store.problem.value;
    if (problem == null || !mounted) return;
    store.problem.value = null;
    showInfoDialog(context, title: problem.title, message: problem.message);
  }

  void _select(AppTab tab) => setState(() => _tab = tab);

  void _openCapture() => startScan(context);

  void _showAddSheet() {
    if (_tab == AppTab.study) {
      showTaskEditor(context);
      return;
    }
    final options = <(IconData, String, VoidCallback)>[
      (AppIcons.capture, 'Scan Notes', _openCapture),
      (AppIcons.newCards, 'New Flashcard Set', () => createSet(context)),
      (AppIcons.newFolder, 'New Folder', () => createFolder(context)),
      (AppIcons.newTask, 'New Task', () => showTaskEditor(context)),
    ];

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, label, action) in options)
              ListTile(
                leading: Icon(icon, color: AppColors.ink),
                title: Text(label, style: AppText.itemTitle),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppColors.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab.index,
            children: [
              DashboardScreen(
                onOpenLibrary: () => _select(AppTab.library),
                onOpenStudy: () => _select(AppTab.study),
                onCapture: _openCapture,
                onOpenProfile: () => _select(AppTab.profile),
              ),
              LibraryScreen(onCapture: _openCapture),
              const StudyScreen(),
              const ProfileScreen(),
            ],
          ),
        ),
        floatingActionButton: _tab == AppTab.profile
            ? null
            : AddFab(onPressed: _showAddSheet),
        bottomNavigationBar: AppBottomNav(
          current: _tab,
          onTabSelected: _select,
          onCameraPressed: _openCapture,
        ),
      ),
    );
  }
}
