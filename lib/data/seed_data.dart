import '../models/models.dart';

/// What a brand-new install starts with, so the app isn't empty on first
/// launch. Everything here can be edited or deleted by the user.
class SeedData {
  SeedData._();

  static final _created = DateTime(2026, 9, 1);

  static const folders = [
    StudyFolder(id: 'f-biology', name: 'Biology', colorValue: 0xFFA8DCC1),
    StudyFolder(id: 'f-language', name: 'Language', colorValue: 0xFFF5B5C8),
    StudyFolder(id: 'f-html', name: 'HTML', colorValue: 0xFFF9C9A3),
    StudyFolder(id: 'f-physics', name: 'Physics', colorValue: 0xFFC7B8F5),
    StudyFolder(id: 'f-css', name: 'CSS', colorValue: 0xFFA9CFF5),
  ];

  static List<StudyTask> tasks() => [
        StudyTask(
            id: 't-cert',
            title: 'Do Certifications',
            pomodorosTotal: 8,
            pomodorosDone: 4,
            focusMinutes: 100,
            createdAt: _created),
        StudyTask(
            id: 't-mod1',
            title: 'Study Module 1',
            pomodorosTotal: 6,
            pomodorosDone: 2,
            focusMinutes: 50,
            createdAt: _created),
        StudyTask(
            id: 't-mod2',
            title: 'Study Module 2',
            pomodorosTotal: 6,
            pomodorosDone: 1,
            focusMinutes: 25,
            createdAt: _created),
        StudyTask(
            id: 't-problems',
            title: 'Solve Problems 1, 2, 3',
            pomodorosTotal: 4,
            pomodorosDone: 3,
            focusMinutes: 75,
            createdAt: _created),
        StudyTask(
            id: 't-wire',
            title: 'Practice Wireframing',
            pomodorosTotal: 4,
            createdAt: _created),
      ];
}
