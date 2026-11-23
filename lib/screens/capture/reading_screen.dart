import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/scan_service.dart';
import '../../services/study_ai.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../utils/format.dart';
import 'captured_page.dart';

/// The pages, cropped and turned upright, and the text read from them.
class ReadPages {
  const ReadPages({
    required this.jpegs,
    required this.pages,
    required this.key,
    this.notice,
  });

  final List<Uint8List> jpegs;

  /// The text read from each page (empty pages where none was found, or
  /// where text isn't read, as on the web).
  final List<RecognizedPage> pages;

  /// The pages' crops and turns when they were read ([readKey]): read
  /// again only if the user changes them.
  final String key;

  /// Something the user should know about how the pages were read (Claude
  /// couldn't read some of them), or null.
  final String? notice;

  String get text => RecognizedPage.join(pages);

  int get wordCount => countWords(text);
}

/// Server answers that will be the same for every page: once one comes,
/// the rest of the pages aren't sent.
const _stopsClaudeReading = {
  'not_set',
  'offline',
  'unauthorized',
  'daily_limit',
  'budget',
  'rate_limited',
  'server_key',
  'server_setup',
  'not_found',
};

/// At most this many pages are with Claude at once.
const _claudeAtOnce = 3;

/// Words in [text]: runs of characters with a letter or digit in them.
int countWords(String text) => text
    .split(RegExp(r'\s+'))
    .where((w) => w.contains(RegExp(r'[\p{L}\p{N}]', unicode: true)))
    .length;

/// Identifies [pages] as they are cropped and turned now.
String readKey(List<CapturedPage> pages) => [
      for (final p in pages)
        '${p.id}:${p.quarterTurns}:'
            '${p.corners.map((c) => '${c.dx.toStringAsFixed(4)},${c.dy.toStringAsFixed(4)}').join(';')}',
    ].join('|');

/// After Next on the crop screen: each page is cropped, then its text read
/// on the phone, page by page, while the page shows with a line sweeping
/// down it and the lines found lit up. With Smart Study's Read Photos with
/// Claude on, each page's photo then goes to the study server and Claude
/// writes out its text (a few pages at once, while the next ones are read
/// on the phone); a page Claude couldn't read keeps the phone's text.
/// Pops with the [ReadPages], or null when cancelled. Where text isn't read
/// (the web without a study server), the pages are only prepared.
class ReadingScreen extends StatefulWidget {
  const ReadingScreen({super.key, required this.pages});

  final List<CapturedPage> pages;

  /// How long a read page stays up with its lines lit (none in tests).
  static Duration pause = const Duration(milliseconds: 450);

  /// Reads [pages] on this screen; null when cancelled or it failed (the
  /// screen says so).
  static Future<ReadPages?> read(BuildContext context, List<CapturedPage> pages) =>
      Navigator.of(context).push<ReadPages>(
        PageRouteBuilder(
          opaque: true,
          transitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (_, _, _) => ReadingScreen(pages: pages),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  final _jpegs = <Uint8List>[];
  final _read = <RecognizedPage>[];
  bool _cancelled = false;
  bool _failed = false;

  /// The page on screen and whether it has been read (its lines lit).
  int _index = 0;
  bool _pageRead = false;

  /// Claude reads the photos too (decided once, when the screen opens).
  late final bool _byClaude = StudyAi.readsPhotos;
  final _claudeCancel = CancelToken();
  final _claudeSlots = _Slots(_claudeAtOnce);

  /// Pages Claude has finished with (read or not), and those it couldn't
  /// read, with the first reason.
  int _claudeDone = 0;
  int _claudeFailed = 0;
  String? _claudeProblem;
  bool _claudeStopped = false;

  /// Every page is on the phone's side done; Claude is still reading.
  bool _waitingForClaude = false;

  bool get _readsOnPhone => ScanService.canReadText;
  bool get _readsText => _readsOnPhone || _byClaude;
  int get _count => widget.pages.length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    _cancelled = true;
    _claudeCancel.cancel();
    _sweep.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final key = readKey(widget.pages);
    final claudeReads = <Future<void>>[];
    try {
      for (var i = 0; i < _count; i++) {
        if (_cancelled) return;
        setState(() {
          _index = i;
          _pageRead = false;
        });
        final jpeg = await widget.pages[i].render();
        if (_cancelled) return;
        setState(() => _jpegs.add(jpeg));
        final found = _readsOnPhone
            ? await ScanService.readPages([jpeg])
            : const <RecognizedPage>[];
        if (_cancelled) return;
        setState(() {
          _read.add(found.isEmpty ? const RecognizedPage() : found.first);
          _pageRead = true;
        });
        if (_byClaude) claudeReads.add(_readWithClaude(i, jpeg));
        if (_readsOnPhone && ReadingScreen.pause > Duration.zero) {
          await Future<void>.delayed(ReadingScreen.pause);
        }
      }
      if (claudeReads.isNotEmpty) {
        if (_cancelled) return;
        setState(() => _waitingForClaude = true);
        await Future.wait(claudeReads);
      }
      if (_cancelled || !mounted) return;
      Navigator.of(context).pop(ReadPages(
        jpegs: _jpegs,
        pages: _read,
        key: key,
        notice: _claudeNotice(),
      ));
    } catch (e, st) {
      debugPrint('Reading the pages failed: $e\n$st');
      if (!_cancelled && mounted) setState(() => _failed = true);
    }
  }

  /// Page [i]'s photo to Claude; its text replaces the phone's when it
  /// comes. A page Claude can't read keeps the phone's text.
  Future<void> _readWithClaude(int i, Uint8List jpeg) async {
    await _claudeSlots.take();
    try {
      if (_cancelled) return;
      if (_claudeStopped) {
        _claudeFailed++;
        return;
      }
      final text = await StudyAi.readPage(jpeg, cancel: _claudeCancel);
      if (_cancelled) return;
      // A page Claude found nothing on keeps whatever the phone found.
      if (text.trim().isNotEmpty) _read[i] = _read[i].withTranscript(text);
    } on StudyAiException catch (e) {
      if (e.isCancelled || _cancelled) return;
      debugPrint('Claude could not read page ${i + 1}: ${e.code} ${e.message}');
      _claudeFailed++;
      _claudeProblem ??= e.message;
      if (_stopsClaudeReading.contains(e.code)) _claudeStopped = true;
    } finally {
      _claudeSlots.give();
      if (!_cancelled && mounted) setState(() => _claudeDone++);
    }
  }

  /// What to tell the user when Claude couldn't read some pages.
  String? _claudeNotice() {
    if (_claudeFailed == 0) return null;
    final which = _claudeFailed == _count
        ? (_count == 1 ? 'The page was' : 'The pages were')
        : '$_claudeFailed of $_count pages were';
    final how = _readsOnPhone
        ? '$which read on your phone instead of by AI.'
        : "$which not read: the AI couldn't read ${_count == 1 ? 'it' : 'them'}.";
    return _claudeProblem == null ? how : '$how $_claudeProblem';
  }

  void _cancel() {
    _cancelled = true;
    _claudeCancel.cancel();
    Navigator.of(context).pop();
  }

  /// How far along: cropping and reading on the phone, then Claude.
  double get _progress {
    final prepared =
        _read.length + (_jpegs.length > _read.length ? 0.5 : 0.1);
    if (!_byClaude) return (prepared / _count).clamp(0.0, 1.0);
    // Half a page's share for the phone's part, half for Claude's.
    return ((prepared * 0.5 + _claudeDone * 0.5) / _count).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final words = countWords(RecognizedPage.join(_read));
    final title = _failed
        ? "Couldn't read the pages"
        : _waitingForClaude
            ? 'AI is reading your notes…'
            : _readsText
                ? 'Reading your notes…'
                : 'Getting your pages ready…';
    final detail = _failed
        ? 'Something went wrong. Go back and tap Next to try again.'
        : _waitingForClaude
            ? (_count == 1
                ? 'Writing out the text on your page'
                : '$_claudeDone of $_count pages read')
            : _count == 1
                ? (_readsText ? 'Turning your photo into text' : 'One page')
                : 'Page ${_index + 1} of $_count';
    final footnote = words > 0
        ? '${plural(words, 'word')} found so far'
        : _byClaude
            ? 'AI reads your handwriting from the photos.'
            : 'Read on your phone. Nothing is uploaded.';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.cameraBackground,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                  child: IconButton(
                    tooltip: 'Cancel',
                    onPressed: _cancel,
                    icon: const Icon(AppIcons.close, color: Colors.white),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
                  child: Center(
                    child: _PageBeingRead(
                      jpeg: _jpegs.length > _index ? _jpegs[_index] : null,
                      fallback: widget.pages[_index],
                      lines: _pageRead && _read.length > _index
                          ? _read[_index].lines
                          : const [],
                      // The sweep runs while the phone reads the page,
                      // and again over its lit lines while Claude reads.
                      sweep: _failed || (_pageRead && !_waitingForClaude)
                          ? null
                          : _sweep,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                child: Column(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(detail,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 16),
                    if (!_failed)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 6,
                          backgroundColor: Colors.white12,
                          color: AppColors.accent,
                        ),
                      ),
                    const SizedBox(height: 14),
                    if (_failed)
                      FilledButton(
                        onPressed: _cancel,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onFill,
                        ),
                        child: const Text('Go Back'),
                      )
                    else if (_readsText)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_byClaude ? AppIcons.suggest : AppIcons.locked,
                              size: 13, color: Colors.white54),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              footnote,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page on screen: the cropped page once it's ready (the photo before
/// that), a line sweeping down it while it's read, then the lines of text
/// found, lit up.
class _PageBeingRead extends StatelessWidget {
  const _PageBeingRead({
    required this.jpeg,
    required this.fallback,
    required this.lines,
    required this.sweep,
  });

  final Uint8List? jpeg;
  final CapturedPage fallback;
  final List<RecognizedLine> lines;
  final Animation<double>? sweep;

  @override
  Widget build(BuildContext context) {
    final size = jpeg == null ? null : jpegSize(jpeg!);
    final aspect = size == null
        ? fallback.displayAspectRatio
        : size.width / size.height;
    final image = jpeg != null
        ? Image.memory(jpeg!, fit: BoxFit.fill, gaplessPlayback: true)
        : RotatedBox(
            quarterTurns: fallback.quarterTurns,
            child: Image.memory(fallback.bytes,
                fit: BoxFit.cover, gaplessPlayback: true),
          );
    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        decoration: BoxDecoration(
          // A blank page while the photo is still being decoded.
          color: const Color(0xFFE9EAEE),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final scale = size == null ? 0.0 : box.maxWidth / size.width;
          return Stack(
            fit: StackFit.expand,
            children: [
              image,
              // Dimmed while being read, so the sweep and the lines show.
              ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
              if (scale > 0)
                for (final l in lines)
                  Positioned(
                    left: l.left * scale - 2,
                    top: l.top * scale - 1,
                    width: (l.right - l.left) * scale + 4,
                    height: (l.bottom - l.top) * scale + 2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: AppColors.accent, width: 1),
                      ),
                    ),
                  ),
              if (sweep case final sweep?)
                AnimatedBuilder(
                  animation: sweep,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(sweep.value);
                    return Align(
                      alignment: Alignment(0, -1 + 2 * t),
                      child: Container(
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppColors.accent.withValues(alpha: 0),
                              AppColors.accent.withValues(alpha: 0.55),
                              AppColors.accent.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// A few places to take, waited for in turn when all are taken.
class _Slots {
  _Slots(this._free);

  int _free;
  final _waiting = <Completer<void>>[];

  Future<void> take() {
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    return turn.future;
  }

  void give() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _free++;
    }
  }
}

/// A JPEG's width and height from its frame header, or null.
Size? jpegSize(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0–SOF15, except DHT (C4), JPG (C8) and DAC (CC).
    if (marker >= 0xC0 && marker <= 0xCF &&
        marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
      final height = (b[i + 5] << 8) | b[i + 6];
      final width = (b[i + 7] << 8) | b[i + 8];
      return width > 0 && height > 0
          ? Size(width.toDouble(), height.toDouble())
          : null;
    }
    i += 2 + length;
  }
  return null;
}
