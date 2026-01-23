// Web implementation using dart:html
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

bool isIOSImpl() {
  final userAgent = html.window.navigator.userAgent;
  final result = userAgent.contains('iPhone') || userAgent.contains('iPad');
  debugPrint('isIOSImpl: userAgent=$userAgent, result=$result');
  return result;
}

bool isAndroidImpl() {
  final userAgent = html.window.navigator.userAgent;
  final result = userAgent.contains('Android');
  debugPrint('isAndroidImpl: userAgent=$userAgent, result=$result');
  return result;
}

bool isStandaloneImpl() {
  final result = html.window.matchMedia('(display-mode: standalone)').matches;
  debugPrint('isStandaloneImpl: result=$result');
  return result;
}

bool isMobileWebImpl() {
  final standalone = isStandaloneImpl();
  final ios = isIOSImpl();
  final android = isAndroidImpl();
  final result = !standalone && (ios || android);
  debugPrint(
    'isMobileWebImpl: standalone=$standalone, ios=$ios, android=$android, result=$result',
  );
  return result;
}
