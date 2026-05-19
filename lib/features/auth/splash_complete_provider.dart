import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the splash screen animation has completed.
/// Used to coordinate entrance animations in the dashboard.
class SplashCompleteNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markComplete() {
    state = true;
  }
}

final splashCompleteProvider =
    NotifierProvider<SplashCompleteNotifier, bool>(SplashCompleteNotifier.new);
