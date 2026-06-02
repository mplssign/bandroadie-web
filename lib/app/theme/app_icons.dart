import 'package:flutter/widgets.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

/// Central icon registry for BandRoadie.
/// Always use AppIcons.* instead of LucideIcons.* or Icons.*

class AppIcons {
  AppIcons._();

  // =============================
  // Navigation
  // =============================

  static const IconData home = LucideIcons.house;
  static const IconData setlists = LucideIcons.listMusic;
  static const IconData calendar = LucideIcons.calendar;
  static const IconData members = LucideIcons.users;

  static const IconData menu = LucideIcons.menu;

  static const IconData back = LucideIcons.chevronLeft;
  static const IconData forward = LucideIcons.chevronRight;

  static const IconData arrowLeft = LucideIcons.arrowLeft;
  static const IconData arrowRight = LucideIcons.arrowRight;
  static const IconData arrowUp = LucideIcons.arrowUp;

  // =============================
  // Core Actions
  // =============================

  static const IconData add = LucideIcons.plus;
  static const IconData remove = LucideIcons.minus;
  static const IconData close = LucideIcons.x;

  static const IconData check = LucideIcons.check;

  static const IconData edit = LucideIcons.pencil;
  static const IconData delete = LucideIcons.trash2;

  static const IconData copy = LucideIcons.copy;
  static const IconData share = LucideIcons.share;

  static const IconData search = LucideIcons.search;
  static const IconData refresh = LucideIcons.refreshCw;

  static const IconData drag = LucideIcons.gripVertical;

  // =============================
  // Status / Alerts
  // =============================

  static const IconData success = LucideIcons.circleCheck;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData info = LucideIcons.info;

  static const IconData ban = LucideIcons.ban;

  // =============================
  // Music / Setlists
  // =============================

  static const IconData music = LucideIcons.music;

  // Lucide doesn't have musicOff
  static const IconData musicOff = LucideIcons.volumeOff;

  static const IconData lyrics = LucideIcons.micVocal;

  static const IconData play = LucideIcons.play;
  static const IconData pause = LucideIcons.pause;

  static const IconData star = LucideIcons.star;

  static const IconData library = LucideIcons.library;

  // =============================
  // Calendar / Events
  // =============================

  static const IconData calendarCheck = LucideIcons.calendarCheck;
  static const IconData calendarX = LucideIcons.calendarX;
  static const IconData calendarDays = LucideIcons.calendarDays;

  static const IconData clock = LucideIcons.clock;
  static const IconData timer = LucideIcons.timer;

  static const IconData location = LucideIcons.mapPin;

  // =============================
  // Users / Members
  // =============================

  static const IconData user = LucideIcons.user;
  static const IconData users = LucideIcons.users;

  static const IconData userAdd = LucideIcons.userPlus;
  static const IconData userRemove = LucideIcons.userMinus;
  static const IconData userCheck = LucideIcons.userCheck;
  static const IconData crown = LucideIcons.crown;

  static const IconData phone = LucideIcons.phone;
  static const IconData email = LucideIcons.mail;

  // =============================
  // Notifications
  // =============================

  static const IconData bell = LucideIcons.bell;
  static const IconData bellOff = LucideIcons.bellOff;
  static const IconData bellRing = LucideIcons.bellRing;

  // =============================
  // System / Settings
  // =============================

  static const IconData settings = LucideIcons.settings;
  static const IconData logout = LucideIcons.logOut;

  static const IconData download = LucideIcons.download;
  static const IconData upload = LucideIcons.upload;
  static const IconData database = LucideIcons.database;
  static const IconData rotateCcw = LucideIcons.rotateCcw;

  static const IconData bug = LucideIcons.bug;
  static const IconData terminal = LucideIcons.terminal;

  // =============================
  // Media
  // =============================

  static const IconData camera = LucideIcons.camera;
  static const IconData image = LucideIcons.image;

  // =============================
  // Marketing / Landing
  // =============================

  static const IconData mic = LucideIcons.mic;
  static const IconData headphones = LucideIcons.headphones;
  static const IconData smartphone = LucideIcons.smartphone;
  static const IconData globe = LucideIcons.globe;

  static const IconData sparkles = LucideIcons.sparkles;

  static const IconData dollar = LucideIcons.dollarSign;
  static const IconData message = LucideIcons.messageSquare;
}
