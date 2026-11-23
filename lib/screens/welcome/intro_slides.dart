import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../../widgets/app_logo.dart';
import '../home_shell.dart';

/// One slide about the app: a picture made of the app's own pieces, a title
/// and a line or two.
class IntroSlide {
  const IntroSlide({
    required this.title,
    required this.body,
    required this.color,
    required this.chips,
    this.icon,
  });

  final String title;
  final String body;

  /// The pastel behind the picture.
  final Color color;

  /// The big icon in the middle (null: the logo).
  final IconData? icon;

  /// Small labels floating around the picture, like bits of the app.
  final List<(IconData, String)> chips;
}

/// What tAsikaso is about, in a few slides, after the welcome screen. Shown
/// once: Skip or Get Started marks it seen and opens the app.
class IntroSlides extends StatefulWidget {
  const IntroSlides({super.key});

  static List<IntroSlide> slides(String name) => [
        IntroSlide(
          title: name.isEmpty ? 'Welcome to $kAppName!' : 'Welcome, $name!',
          body: '$kAppName keeps your studying in one place: a timer to '
              'focus, your class notes, and flashcards made from them.',
          color: const Color(0xFF9FCBF5),
          chips: const [
            (AppIcons.timer, 'Pomodoro'),
            (AppIcons.notebook, 'Notes'),
            (AppIcons.flashcards, 'Flashcards'),
          ],
        ),
        const IntroSlide(
          title: 'Focus with Pomodoro',
          body: 'Study in 25-minute Pomodoros with short breaks in between. '
              'Pick a task and watch your progress and streak grow.',
          color: Color(0xFFF9C9A3),
          icon: AppIcons.timer,
          chips: [(AppIcons.clock, '25:00'), (AppIcons.streak, '3-day streak')],
        ),
        const IntroSlide(
          title: 'Snap your notes into text',
          body: 'Take photos of your lecture notes. $kAppName crops the pages '
              'and reads the text right on your phone.',
          color: Color(0xFFA8DCC1),
          icon: AppIcons.capture,
          chips: [(AppIcons.pages, '3 pages'), (AppIcons.text, 'Text found')],
        ),
        const IntroSlide(
          title: 'A Notebook in every folder',
          body: 'Save notes to a folder, like Biology or Physics. Each folder '
              'has its own Notebook, so your notes stay organised.',
          color: Color(0xFFC7B8F5),
          icon: AppIcons.notebook,
          chips: [(AppIcons.folderOpen, 'Biology'), (AppIcons.newNote, 'Cells')],
        ),
        const IntroSlide(
          title: 'Turn notes into flashcards',
          body: 'Make flashcards from any note in a tap, put them in a new or '
              'existing set, and review them to remember more.',
          color: Color(0xFFF5B5C8),
          icon: AppIcons.flashcards,
          chips: [(AppIcons.newCards, '12 cards'), (AppIcons.due, '5 due')],
        ),
      ];

  @override
  State<IntroSlides> createState() => _IntroSlidesState();
}

class _IntroSlidesState extends State<IntroSlides> {
  final _store = AppStore.instance;
  final _pages = PageController();
  int _index = 0;

  late final List<IntroSlide> _slides =
      IntroSlides.slides(_store.prefs.userName.trim().split(RegExp(r'\s+')).first);

  bool get _last => _index == _slides.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) return _finish();
    _pages.nextPage(
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  void _finish() {
    _store.updatePrefs(_store.prefs.copyWith(welcomed: true));
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const HomeShell(),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AnimatedOpacity(
                    opacity: _last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: _last ? null : _finish,
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary),
                      child: const Text('Skip',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [for (final s in _slides) _SlideView(s)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  _Dots(count: _slides.length, index: _index),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onFill,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_last ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Icon(_last ? AppIcons.doneCircle : AppIcons.nextCircle,
                              size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView(this.slide);

  final IntroSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Picture(slide, size: box.maxHeight < 420 ? 190 : 250),
              const SizedBox(height: 28),
              Text(slide.title,
                  textAlign: TextAlign.center,
                  style: AppText.screenTitle.copyWith(fontSize: 24)),
              const SizedBox(height: 10),
              Text(slide.body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pastel circle with the slide's icon (or the logo) on a card in the
/// middle, and its chips around it.
class _Picture extends StatelessWidget {
  const _Picture(this.slide, {required this.size});

  final IntroSlide slide;
  final double size;

  static const _spots = [
    Alignment(-1, -0.72),
    Alignment(1, 0.62),
    Alignment(0.95, -0.95),
  ];

  @override
  Widget build(BuildContext context) {
    final card = size * 0.42;
    return ExcludeSemantics(
      child: SizedBox(
        width: size * 1.12,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size * 0.86,
              height: size * 0.86,
              decoration: BoxDecoration(
                color: AppColors.tint(slide.color, 0.55),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: card,
              height: card,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(card * 0.28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: slide.icon == null
                  ? AppLogo(size: card * 0.7)
                  : Icon(slide.icon,
                      size: card * 0.5,
                      color: AppColors.deepen(slide.color, 0.45)),
            ),
            for (final (i, (icon, label)) in slide.chips.indexed)
              Align(
                alignment: _spots[i % _spots.length],
                child: _Chip(icon: icon, label: label, color: slide.color),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: AppColors.raised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.deepen(color, 0.45)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Slide ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == index ? AppColors.primaryDeep : AppColors.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}
