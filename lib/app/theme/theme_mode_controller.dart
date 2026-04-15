import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadFromPrefs();
    return ThemeMode.dark;
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLight = prefs.getBool('light_mode_enabled') ?? false;
      if (isLight) {
        state = ThemeMode.light;
      }
    } catch (_) {
      // private browsing or storage unavailable — stay dark
    }
  }

  Future<void> toggle() async {
    final isLight = state == ThemeMode.light;
    state = isLight ? ThemeMode.dark : ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('light_mode_enabled', !isLight);
    } catch (_) {
      // persist failure is non-fatal
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
