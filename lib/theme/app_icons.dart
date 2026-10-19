import 'package:flutter/widgets.dart';

const _light = 'PhosphorLight';
const _fill = 'PhosphorFill';

/// Every icon the app uses, in one place.
///
/// Phosphor icons (phosphoricons.com): "Light" (thin, rounded strokes) for a
/// minimal look, "Fill" only for the selected tab, the streak flame and the
/// timer button. The fonts are bundled in assets/fonts (see pubspec.yaml).
/// Code points come from Phosphor 2.1; the comment after each is its name.
class AppIcons {
  AppIcons._();

  // Bottom bar
  static const IconData dashboard = IconData(0xe464, fontFamily: _light); // squaresFour
  static const IconData dashboardActive = IconData(0xe464, fontFamily: _fill); // squaresFour
  static const IconData library = IconData(0xe758, fontFamily: _light); // books
  static const IconData libraryActive = IconData(0xe758, fontFamily: _fill); // books
  static const IconData study = IconData(0xe492, fontFamily: _light); // timer
  static const IconData studyActive = IconData(0xe492, fontFamily: _fill); // timer
  static const IconData profile = IconData(0xe4c2, fontFamily: _light); // user
  static const IconData profileActive = IconData(0xe4c2, fontFamily: _fill); // user
  /// Main capture button.
  static const IconData capture = IconData(0xe10e, fontFamily: _light); // camera

  // General
  static const IconData settings = IconData(0xe272, fontFamily: _light); // gearSix
  static const IconData search = IconData(0xe30c, fontFamily: _light); // magnifyingGlass
  static const IconData more = IconData(0xe208, fontFamily: _light); // dotsThreeVertical
  static const IconData add = IconData(0xe3d4, fontFamily: _light); // plus
  static const IconData streak = IconData(0xe242, fontFamily: _fill); // fire
  static const IconData chevronDown = IconData(0xe136, fontFamily: _light); // caretDown
  static const IconData chevronRight = IconData(0xe13a, fontFamily: _light); // caretRight
  static const IconData check = IconData(0xe182, fontFamily: _light); // check
  static const IconData close = IconData(0xe4f6, fontFamily: _light); // x
  static const IconData back = IconData(0xe058, fontFamily: _light); // arrowLeft
  static const IconData play = IconData(0xe3d0, fontFamily: _light); // play
  static const IconData minus = IconData(0xe32a, fontFamily: _light); // minus
  static const IconData edit = IconData(0xe3b4, fontFamily: _light); // pencilSimple
  static const IconData done = IconData(0xe184, fontFamily: _light); // checkCircle
  static const IconData chevronUp = IconData(0xe13c, fontFamily: _light); // caretUp
  static const IconData folderOpen = IconData(0xe256, fontFamily: _light); // folderOpen
  static const IconData folder = IconData(0xe24a, fontFamily: _fill); // folder
  static const IconData again = IconData(0xe096, fontFamily: _light); // arrowsCounterClockwise
  static const IconData photo = IconData(0xe2ca, fontFamily: _light); // image
  static const IconData next = IconData(0xe06c, fontFamily: _light); // arrowRight
  static const IconData chevronLeft = IconData(0xe138, fontFamily: _light); // caretLeft
  static const IconData copy = IconData(0xe1ca, fontFamily: _light); // copy
  static const IconData calendar = IconData(0xe10a, fontFamily: _light); // calendarBlank

  // Analysis
  static const IconData chart = IconData(0xe150, fontFamily: _light); // chartBar
  static const IconData clock = IconData(0xe19a, fontFamily: _light); // clock
  static const IconData target = IconData(0xe47c, fontFamily: _light); // target
  static const IconData trophy = IconData(0xe67e, fontFamily: _light); // trophy
  static const IconData morning = IconData(0xe5b6, fontFamily: _light); // sunHorizon
  static const IconData afternoon = IconData(0xe472, fontFamily: _light); // sun
  static const IconData evening = IconData(0xe53e, fontFamily: _light); // cloudMoon
  static const IconData night = IconData(0xe58e, fontFamily: _light); // moonStars

  // Plus subscription
  static const IconData plus = IconData(0xe614, fontFamily: _fill); // crown
  static const IconData plusLight = IconData(0xe614, fontFamily: _light); // crown
  static const IconData included = IconData(0xe184, fontFamily: _fill); // checkCircle
  static const IconData locked = IconData(0xe308, fontFamily: _light); // lockSimple

  // Text recognition
  static const IconData text = IconData(0xe484, fontFamily: _light); // textAlignLeft
  static const IconData suggest = IconData(0xe6a2, fontFamily: _light); // sparkle
  static const IconData smartScan = IconData(0xe6b6, fontFamily: _light); // magicWand

  // Timer
  static const IconData start = IconData(0xe3d0, fontFamily: _fill); // play
  static const IconData pause = IconData(0xe39e, fontFamily: _fill); // pause
  static const IconData reset = IconData(0xe038, fontFamily: _light); // arrowCounterClockwise
  static const IconData skip = IconData(0xe5a6, fontFamily: _light); // skipForward

  // Create
  static const IconData newTask = IconData(0xeadc, fontFamily: _light); // listChecks
  static const IconData newFolder = IconData(0xe258, fontFamily: _light); // folderPlus
  static const IconData newNote = IconData(0xe34c, fontFamily: _light); // notePencil
  static const IconData newCards = IconData(0xe0f8, fontFamily: _light); // cards

  // Capture & crop
  static const IconData flashOn = IconData(0xe2de, fontFamily: _light); // lightning
  static const IconData flashOff = IconData(0xe2e0, fontFamily: _light); // lightningSlash
  static const IconData gallery = IconData(0xe836, fontFamily: _light); // images
  static const IconData scan = IconData(0xebb6, fontFamily: _light); // scan
  static const IconData share = IconData(0xe408, fontFamily: _light); // shareNetwork
  static const IconData warning = IconData(0xe4e0, fontFamily: _light); // warning
  static const IconData rotate = IconData(0xe036, fontFamily: _light); // arrowClockwise
  static const IconData resetCrop = IconData(0xe626, fontFamily: _light); // frameCorners
  static const IconData addPhoto = IconData(0xec58, fontFamily: _light); // cameraPlus
  static const IconData delete = IconData(0xe4a6, fontFamily: _light); // trash
  static const IconData pdf = IconData(0xe702, fontFamily: _light); // filePdf
  static const IconData flashcards = IconData(0xe0f8, fontFamily: _light); // cards

  // Profile
  static const IconData pomodoroSettings = IconData(0xe492, fontFamily: _light); // timer
  static const IconData notifications = IconData(0xe0ce, fontFamily: _light); // bell
  static const IconData backup = IconData(0xe1ae, fontFamily: _light); // cloudArrowUp
  static const IconData help = IconData(0xe3e8, fontFamily: _light); // question
  static const IconData signOut = IconData(0xe42a, fontFamily: _light); // signOut
  static const IconData avatar = IconData(0xe4c2, fontFamily: _fill); // user
}
