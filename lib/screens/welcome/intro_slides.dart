import 'package:flutter/material.dart';

import '../../data/app_store.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/brand.dart';
import '../../widgets/app_logo.dart';
import '../home_shell.dart';

/// Which piece of the app a slide shows in its picture.
enum IntroPeek { home, timer, scan, notebook, cards }

/// One slide about the app: a peek at the real screen it is about (on the
/// slide's pastel), a title and a line or two.
class IntroSlide {
  const IntroSlide({
    required this.title,
    required this.body,
    required this.color,
    required this.peek,
  });

  final String title;
  final String body;

  /// The pastel behind the picture.
  final Color color;

  /// The screen peeking up from the bottom of the picture.
  final IntroPeek peek;
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
          peek: IntroPeek.home,
        ),
        const IntroSlide(
          title: 'Focus with Pomodoro',
          body: 'Study in 25-minute Pomodoros with short breaks in between. '
              'Pick a task and watch your progress and streak grow.',
          color: Color(0xFFF9C9A3),
          peek: IntroPeek.timer,
        ),
        const IntroSlide(
          title: 'Snap your notes into text',
          body: 'Take photos of your lecture notes. $kAppName crops the pages '
              'and Claude reads the text, even handwriting.',
          color: Color(0xFFA8DCC1),
          peek: IntroPeek.scan,
        ),
        const IntroSlide(
          title: 'A Notebook in every folder',
          body: 'Save notes to a folder, like Biology or Physics. Each folder '
              'has its own Notebook, so your notes stay organised.',
          color: Color(0xFFC7B8F5),
          peek: IntroPeek.notebook,
        ),
        const IntroSlide(
          title: 'Turn notes into flashcards',
          body: 'Make flashcards from any note in a tap, put them in a new or '
              'existing set, and review them to remember more.',
          color: Color(0xFFF5B5C8),
          peek: IntroPeek.cards,
        ),
      ];

  @override
  State<IntroSlides> createState() => _IntroSlidesState();
}

class _IntroSlidesState extends State<IntroSlides> {
  final _store = AppStore.instance;
  final _pages = PageController();
  int _index = 0;

  late final String _firstName =
      _store.prefs.userName.trim().split(RegExp(r'\s+')).first;
  late final List<IntroSlide> _slides = IntroSlides.slides(_firstName);

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
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  PageView(
                    controller: _pages,
                    onPageChanged: (i) => setState(() => _index = i),
                    children: [
                      for (final (i, s) in _slides.indexed)
                        _SlideView(s,
                            number: i + 1,
                            count: _slides.length,
                            name: _firstName,
                            topInset: top),
                    ],
                  ),
                  Positioned(
                    top: top + 10,
                    right: 16,
                    child: AnimatedOpacity(
                      opacity: _last ? 0 : 1,
                      duration: const Duration(milliseconds: 200),
                      child: TextButton(
                        onPressed: _last ? null : _finish,
                        style: TextButton.styleFrom(
                          backgroundColor:
                              AppColors.surface.withValues(alpha: 0.7),
                          foregroundColor: AppColors.ink,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Skip',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 24, 20),
              child: Row(
                children: [
                  _Dots(count: _slides.length, index: _index),
                  const SizedBox(width: 12),
                  // Shrinks a little rather than overflow on a small phone
                  // with large text.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDeep,
                        foregroundColor: AppColors.onPrimaryDeep,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_last ? 'Get Started' : 'Next',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          Icon(_last ? AppIcons.doneCircle : AppIcons.next,
                              size: 20),
                        ],
                      ),
                    ),
                  ),
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

/// One slide: the pastel panel with the app peeking up into it, then the
/// title and text.
class _SlideView extends StatelessWidget {
  const _SlideView(this.slide,
      {required this.number,
      required this.count,
      required this.name,
      required this.topInset});

  final IntroSlide slide;
  final int number;
  final int count;
  final String name;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final panel = (box.maxHeight * 0.56).clamp(220.0, 500.0);
      final sheetWidth = (box.maxWidth - 128).clamp(200.0, 270.0);
      final sheetTop = topInset + 64;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: panel,
            decoration: BoxDecoration(
              color: AppColors.tint(slide.color, 0.55),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 24,
                  top: topInset + 22,
                  child: Text('$number OF $count',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: AppColors.deepen(slide.color, 0.55))),
                ),
                // The app, rising from the bottom edge.
                Positioned(
                  top: sheetTop,
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ExcludeSemantics(
                      child: Container(
                        width: sheetWidth,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28)),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.deepen(slide.color, 0.5)
                                  .withValues(alpha: 0.18),
                              blurRadius: 30,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        // Drawn at one size and scaled to the sheet, like a
                        // picture: the same on every phone and text size.
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minHeight: 0,
                          maxHeight: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.fitWidth,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: 262,
                              child: MediaQuery.withNoTextScaling(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 18, 16, 0),
                                  child: _Peek(slide, name: name),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slide.title,
                      style: AppText.screenTitle
                          .copyWith(fontSize: 27, height: 1.15)),
                  const SizedBox(height: 10),
                  Text(slide.body,
                      style: TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// A small, still copy of the screen a slide is about, built from the
/// app's own colours so it follows light and dark mode.
class _Peek extends StatelessWidget {
  const _Peek(this.slide, {required this.name});

  final IntroSlide slide;
  final String name;

  Color get _deep => AppColors.deepen(slide.color, 0.5);
  Color get _soft => AppColors.tint(slide.color, 0.4);

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: AppColors.ink, fontSize: 12),
      child: switch (slide.peek) {
        IntroPeek.home => _home(),
        IntroPeek.timer => _timer(),
        IntroPeek.scan => _scan(),
        IntroPeek.notebook => _notebook(),
        IntroPeek.cards => _cards(),
      },
    );
  }

  Widget _box({required Widget child, Color? color, EdgeInsets? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color ?? AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _pill(String text, {Color? color, Color? ink}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color ?? AppColors.primary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ink ?? AppColors.onFill)),
      );

  Widget _ring(double value, double size, Widget middle) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: size / 16,
                strokeCap: StrokeCap.round,
                color: AppColors.primaryDeep,
                backgroundColor: AppColors.tint(AppColors.primary, 0.5),
              ),
            ),
            middle,
          ],
        ),
      );

  Widget _home() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const AppLogo(size: 26),
            const SizedBox(width: 8),
            Text(name.isEmpty ? 'Hello!' : 'Hello, $name!',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),
          _box(
            child: Row(children: [
              _ring(
                  0.4,
                  58,
                  const Text('40%',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Today's Focus",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('60 of 150 min',
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    _pill('Start Focus'),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final (icon, label) in const [
              (AppIcons.timer, 'Pomodoro'),
              (AppIcons.notebook, 'Notes'),
              (AppIcons.flashcards, 'Cards'),
            ]) ...[
              Expanded(
                child: _box(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(children: [
                    Icon(icon, size: 20, color: _deep),
                    const SizedBox(height: 4),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 10.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              if (label != 'Cards') const SizedBox(width: 8),
            ],
          ]),
        ],
      );

  Widget _timer() => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, t) in const ['Pomodoro', 'Short Break', 'Long Break'].indexed)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: i == 0
                        ? BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8))
                        : null,
                    child: Text(t,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: i == 0 ? AppColors.ink : AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ring(
            0.68,
            150,
            Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('17:08',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
              Text('Session 2 of 4',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 14),
          _pill('PAUSE'),
          const SizedBox(height: 14),
          _box(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Read chapter 3',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  _pill('Current',
                      color: AppColors.tint(AppColors.primary, 0.5),
                      ink: AppColors.primaryDeep),
                ]),
                const SizedBox(height: 3),
                Text('1 / 4 Pomodoros · 25 / 100 min',
                    style: TextStyle(
                        fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      );

  Widget _scan() {
    Widget line(double w, {bool lit = false}) => Container(
          margin: const EdgeInsets.only(bottom: 9),
          width: w,
          height: 9,
          decoration: BoxDecoration(
            color: lit
                ? AppColors.tint(AppColors.primary, 0.3)
                : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text('Lecture 4',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const Spacer(),
          _pill('3 pages', color: _soft, ink: _deep),
        ]),
        const SizedBox(height: 12),
        _box(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(120, lit: true),
              line(190, lit: true),
              line(160, lit: true),
              line(175),
              line(90),
              line(185),
              line(140),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Icon(AppIcons.suggest, size: 16, color: _deep),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Claude is reading your notes…',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: 0.66,
            minHeight: 6,
            color: AppColors.primaryDeep,
            backgroundColor: AppColors.tint(AppColors.primary, 0.5),
          ),
        ),
        const SizedBox(height: 6),
        Text('2 of 3 pages read',
            style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _notebook() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: _soft, borderRadius: BorderRadius.circular(9)),
              child: Icon(AppIcons.folderOpen, size: 17, color: _deep),
            ),
            const SizedBox(width: 8),
            const Text('Biology',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          Text('3 notes, 2 flashcard sets',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          _box(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(AppIcons.notebook, size: 16, color: _deep),
                  const SizedBox(width: 6),
                  const Text('Biology Notebook',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                for (final (title, date) in const [
                  ('Cells', 'Nov 20'),
                  ('Photosynthesis Lecture', 'Nov 22'),
                  ('Genetics', 'Nov 23'),
                ])
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: AppColors.border))),
                    child: Row(children: [
                      Icon(AppIcons.pages, size: 15, color: AppColors.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Text(date,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textSecondary)),
                    ]),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _cards() => Column(
        children: [
          Row(children: [
            const Text('Cells',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('12 cards · 5 due',
                style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 12),
          Container(
            height: 170,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _soft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('QUESTION',
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _deep)),
                const SizedBox(height: 10),
                const Text('What is the powerhouse of the cell?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
                const SizedBox(height: 10),
                Text('Tap to see the answer',
                    style: TextStyle(fontSize: 10, color: _deep)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _box(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: const Center(
                    child: Text('Again',
                        style: TextStyle(fontWeight: FontWeight.w700))),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _box(
                color: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: const Center(
                    child: Text('Got It',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onFill))),
              ),
            ),
          ]),
        ],
      );
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
        mainAxisSize: MainAxisSize.min,
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
