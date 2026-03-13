// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VersionCheckService {
  static Future<void> checkOncePerSession(String currentBuild) async {
    if (!kIsWeb) return;

    // Only run once per browser session
    if (html.window.sessionStorage['version_checked'] == 'true') return;

    html.window.sessionStorage['version_checked'] = 'true';

    try {
      final response = await http.get(Uri.parse(
          '/version.json?ts=${DateTime.now().millisecondsSinceEpoch}'));

      if (response.statusCode != 200) return;

      final Map<String, dynamic> data = json.decode(response.body);

      final latestBuild = data['build_number']?.toString();

      if (latestBuild != null && latestBuild != currentBuild) {
        html.window.location.reload();
      }
    } catch (_) {
      // Version checks should never break the app
    }
  }
}
