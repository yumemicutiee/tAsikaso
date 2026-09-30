import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import 'captured_page.dart';
import 'review_screen.dart';

enum CaptureMode { single, multiple }

/// Camera screen for photographing lecture notes (board or notebook).
///
/// Single: one photo, then straight to cropping.
/// Multiple: keep shooting; pages collect in a strip until "Done".
/// Photos can also be imported from the gallery.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  /// Finds the device cameras. Tests replace this to run without a camera.
  @visibleForTesting
  static Future<List<CameraDescription>> Function() loadCameras =
      availableCameras;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initializing = true;
  bool _starting = false; // guards against starting the camera twice
  String? _cameraError;

  CaptureMode _mode = CaptureMode.single;
  bool _flashOn = false;

  /// True while a photo is being taken or processed.
  bool _busy = false;

  final List<CapturedPage> _pages = [];
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  // ---- Camera lifecycle ------------------------------------------------------

  Future<void> _initCamera() async {
    if (_starting) return;
    _starting = true;
    try {
      final cameras = await CaptureScreen.loadCameras();
      if (cameras.isEmpty) {
        throw CameraException('NoCamera', 'No camera found.');
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        rethrow;
      }
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _applyFlash(controller);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError = _describeCameraError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _cameraError = "The camera isn't available here. "
            'You can still import photos from your gallery.';
      });
    } finally {
      _starting = false;
    }
  }

  void _restartCamera() {
    setState(() {
      _initializing = true;
      _cameraError = null;
    });
    _initCamera();
  }

  String _describeCameraError(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is turned off. Allow it in your phone '
            'Settings, or import photos from your gallery.';
      case 'NoCamera':
        return 'No camera was found. You can import photos from your gallery.';
      default:
        return "The camera couldn't start. Try again, or import photos "
            'from your gallery.';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera while the app is in the background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = _controller;
      if (c == null) return;
      _controller = null;
      if (mounted) setState(() => _initializing = true);
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _cameraError == null && mounted) {
        _initCamera();
      }
    }
  }

  Future<void> _applyFlash(CameraController c) async {
    try {
      await c.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {
      // Some devices and browsers have no flash; ignore.
    }
  }

  Future<void> _toggleFlash() async {
    setState(() => _flashOn = !_flashOn);
    final c = _controller;
    if (c != null && c.value.isInitialized) await _applyFlash(c);
  }

  // ---- Capturing -------------------------------------------------------------

  Future<void> _onShutter() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || c.value.isTakingPicture || _busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      // Let the spinner paint before decoding (runs on the UI thread on web).
      await WidgetsBinding.instance.endOfFrame;
      final page = await CapturedPage.fromPhoto(_nextId++, await file.readAsBytes());
      if (!mounted) return;
      if (_mode == CaptureMode.single) {
        setState(() => _busy = false);
        await _openReview([page]);
      } else {
        HapticFeedback.lightImpact();
        setState(() => _pages.add(page));
      }
    } catch (_) {
      _showMessage("Couldn't take the photo. Please try again.");
    } finally {
      if (mounted && _busy) setState(() => _busy = false);
    }
  }

  Future<void> _importFromGallery() async {
    if (_busy) return;
    final List<XFile> files;
    try {
      // Downscaled by the picker so huge photos don't have to be decoded here.
      files = await ImagePicker().pickMultiImage(
        maxWidth: CapturedPage.maxSide.toDouble(),
        maxHeight: CapturedPage.maxSide.toDouble(),
      );
    } catch (_) {
      _showMessage("Couldn't open your gallery.");
      return;
    }
    if (files.isEmpty || !mounted) return;

    setState(() => _busy = true);
    await WidgetsBinding.instance.endOfFrame;
    final imported = <CapturedPage>[];
    try {
      for (final f in files) {
        imported.add(await CapturedPage.fromPhoto(_nextId++, await f.readAsBytes()));
      }
    } catch (_) {
      _showMessage('Some photos could not be opened.');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (imported.isEmpty) return;

    final all = [..._pages, ...imported];
    if (all.length > 1) setState(() => _mode = CaptureMode.multiple);
    await _openReview(all);
  }

  Future<void> _openReview(List<CapturedPage> pages) async {
    final kept = await Navigator.of(context).push<List<CapturedPage>>(
      MaterialPageRoute(builder: (_) => ReviewScreen(pages: pages)),
    );
    // After saving, the whole capture flow is closed and we never get here.
    // Coming back ("Add More", "Retake" or Back) keeps the remaining pages.
    if (!mounted || kept == null) return;
    setState(() {
      _pages
        ..clear()
        ..addAll(_mode == CaptureMode.multiple ? kept : const []);
    });
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final multi = _mode == CaptureMode.multiple;
    final canShoot =
        _controller != null && _controller!.value.isInitialized && !_busy;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.cameraBackground,
        body: SafeArea(
          child: Column(
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(AppIcons.close, color: Colors.white),
                    ),
                    const Spacer(),
                    _ModeToggle(
                      mode: _mode,
                      onChanged: (m) => setState(() {
                        _mode = m;
                        if (m == CaptureMode.single) _pages.clear();
                      }),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _flashOn ? 'Flash On' : 'Flash Off',
                      onPressed: _toggleFlash,
                      icon: Icon(
                        _flashOn ? AppIcons.flashOn : AppIcons.flashOff,
                        color: _flashOn ? AppColors.accent : Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Viewfinder
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: _buildViewfinder(),
                ),
              ),

              // Captured pages strip (multiple mode)
              if (multi)
                SizedBox(
                  height: 76,
                  child: _pages.isEmpty
                      ? const Center(
                          child: Text(
                            'Take as many photos as you need',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          itemCount: _pages.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 10),
                          itemBuilder: (context, i) => _Thumb(
                            page: _pages[i],
                            index: i + 1,
                            onRemove: () => setState(() => _pages.removeAt(i)),
                          ),
                        ),
                ),

              // Controls
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 12, 28, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundIconButton(
                      icon: AppIcons.gallery,
                      tooltip: 'Import From Gallery',
                      onPressed: _busy ? null : _importFromGallery,
                    ),
                    _ShutterButton(
                      enabled: canShoot,
                      busy: _busy,
                      onPressed: _onShutter,
                    ),
                    SizedBox(
                      width: 84,
                      child: multi && _pages.isNotEmpty
                          ? FilledButton(
                              onPressed: _busy ? null : () => _openReview(List.of(_pages)),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accent,
                                foregroundColor: AppColors.onFill,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                'Done (${_pages.length})',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            )
                          : null,
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

  Widget _buildViewfinder() {
    final c = _controller;
    final Widget content;
    if (c != null && c.value.isInitialized) {
      content = Center(child: CameraPreview(c, child: const _FrameGuides()));
    } else if (_cameraError != null) {
      content = _CameraMessage(
        message: _cameraError!,
        onRetry: _restartCamera,
        onImport: _importFromGallery,
      );
    } else {
      content = const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: AppColors.cameraPanel,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (c != null && _cameraError == null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Fit the board or page inside the frame',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            if (_busy && !_initializing)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({
    required this.message,
    required this.onRetry,
    required this.onImport,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.warning, size: 40, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onRetry,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white38),
                  ),
                  child: const Text('Try Again'),
                ),
                FilledButton(
                  onPressed: onImport,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onFill,
                  ),
                  child: const Text('Import Photos'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final CaptureMode mode;
  final ValueChanged<CaptureMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(CaptureMode m, String label) {
      final selected = m == mode;
      return GestureDetector(
        onTap: () => onChanged(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onFill : Colors.white70,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(CaptureMode.single, 'Single'),
          pill(CaptureMode.multiple, 'Multiple'),
        ],
      ),
    );
  }
}

/// Corner brackets drawn over the live preview.
class _FrameGuides extends StatelessWidget {
  const _FrameGuides();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: CustomPaint(painter: _FrameGuidePainter()),
    );
  }
}

class _FrameGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    final w = size.width;
    final h = size.height;

    canvas.drawPath(
      Path()
        ..moveTo(0, len)
        ..lineTo(0, 0)
        ..lineTo(len, 0)
        ..moveTo(w - len, 0)
        ..lineTo(w, 0)
        ..lineTo(w, len)
        ..moveTo(w, h - len)
        ..lineTo(w, h)
        ..lineTo(w - len, h)
        ..moveTo(len, h)
        ..lineTo(0, h)
        ..lineTo(0, h - len),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.enabled,
    required this.busy,
    required this.onPressed,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Take Photo',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled || busy ? 1 : 0.4,
          child: Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.onFill),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
            fixedSize: const Size(50, 50),
          ),
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.page, required this.index, required this.onRemove});

  final CapturedPage page;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // 6px extra on the top and right so the remove button is fully tappable.
    return SizedBox(
      width: 56,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 6,
            right: 6,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: RotatedBox(
                quarterTurns: page.quarterTurns,
                child: Image.memory(
                  page.bytes,
                  fit: BoxFit.cover,
                  cacheWidth: 120,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.onFill.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('$index',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.close, size: 13, color: AppColors.onFill),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
