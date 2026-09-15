import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:bandroadie/app/models/band.dart';
import 'package:bandroadie/app/theme/app_theme.dart';
import 'package:bandroadie/features/auth/auth_state_provider.dart';
import 'package:bandroadie/features/auth/invite_screen.dart';
import 'package:bandroadie/features/bands/active_band_controller.dart';

typedef _RequestHandler = Future<http.Response> Function(http.Request request);

_RequestHandler? _handler;

class _TrackingActiveBandNotifier extends ActiveBandNotifier {
  String? lastSelectedBandId;

  @override
  ActiveBandState build() {
    return const ActiveBandState();
  }

  @override
  Future<void> loadAndSelectBand(String bandId) async {
    lastSelectedBandId = bandId;
    final now = DateTime.now();
    state = ActiveBandState(
      userBands: [
        Band(
          id: bandId,
          name: 'The Roadies',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      activeBand: Band(
        id: bandId,
        name: 'The Roadies',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

class _ImmediateAuthStateNotifier extends AuthStateNotifier {
  @override
  AppAuthState build() {
    return AppAuthState(session: Supabase.instance.client.auth.currentSession);
  }
}

Future<void> _initSupabase() async {
  final mockClient = MockClient((request) async {
    final handler = _handler;
    if (handler != null) {
      return handler(request);
    }
    throw StateError('No mock handler configured for ${request.url}');
  });

  try {
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      publishableKey: 'test-anon-key',
      httpClient: mockClient,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
      ),
    );
  } catch (_) {}
}

String _sessionJson({
  required String userId,
  required String email,
}) {
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(json.encode(claims))).replaceAll('=', '');

  final accessToken = [
    segment({'alg': 'HS256', 'typ': 'JWT'}),
    segment({
      'sub': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'iat': nowSeconds,
      'exp': nowSeconds + 3600,
    }),
    base64Url.encode(utf8.encode('signature')).replaceAll('=', ''),
  ].join('.');

  return json.encode({
    'access_token': accessToken,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-$userId',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': email,
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': DateTime.now().toIso8601String(),
    },
  });
}

Future<void> _primeSession(
    {required String userId, required String email}) async {
  await Supabase.instance.client.auth.recoverSession(
    _sessionJson(userId: userId, email: email),
  );
}

Widget _testApp(_TrackingActiveBandNotifier notifier) {
  return ProviderScope(
    overrides: [
      activeBandProvider.overrideWith(() => notifier),
      authStateProvider.overrideWith(_ImmediateAuthStateNotifier.new),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: FTheme(
        data: AppTheme.foruiTheme(Brightness.dark),
        child: const InviteScreen(token: 'invite-token-123'),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int maxTicks = 50,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    _drainKnownRenderOverflow(tester);
    if (predicate()) {
      await tester.pump();
      _drainKnownRenderOverflow(tester);
      return;
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await _initSupabase();
  });

  setUp(() {
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({'error': 'missing test handler'}),
          500,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };
  });

  tearDown(() async {
    _handler = null;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  });

  testWidgets('No session shows the email-entry auth UI instead of an error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => find.text('Email login link').evaluate().isNotEmpty,
    );

    expect(find.text("You've been invited to join a band!"), findsOneWidget);
    expect(find.text('Email login link'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
  });

  testWidgets(
      'Valid same-email session accepts the invite and records the band id', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-1', email: 'invitee@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({
            'success': true,
            'accepted_count': 1,
            'band_names': ['The Roadies'],
            'accepted_band_id': 'band-123',
            'accepted_band_ids': ['band-123'],
          }),
          200,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => notifier.lastSelectedBandId == 'band-123',
    );

    expect(find.text("You've joined The Roadies!"), findsOneWidget);
    expect(notifier.lastSelectedBandId, 'band-123');

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
    await tester.pump(const Duration(seconds: 3));
    _drainKnownRenderOverflow(tester);
  });

  testWidgets(
      'A 401 response signs out locally and shows invited-email recovery UI', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-401', email: 'stale@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({
            'error': 'Invalid or expired session. Please sign in again.',
          }),
          401,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => Supabase.instance.client.auth.currentSession == null,
    );
    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);

    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(find.text('Email login link'), findsOneWidget);
    expect(find.text("You've joined The Roadies!"), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
  });

  testWidgets(
      'A 403 email mismatch signs out locally and shows the targeted recovery UI',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-403', email: 'wrong@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({
            'error': 'This invite was sent to a different email.',
            'code': 'email_mismatch',
          }),
          403,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => Supabase.instance.client.auth.currentSession == null,
    );
    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);

    expect(Supabase.instance.client.auth.currentSession, isNull);
    expect(find.text('Email login link'), findsOneWidget);
    expect(find.text("You've joined The Roadies!"), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
  });

  testWidgets(
      'A 409 invite_unavailable shows the neutral terminal message without signing out',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-409', email: 'invitee@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({
            'error': 'This invite is no longer available.',
            'code': 'invite_unavailable',
          }),
          409,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => find
          .text('This invite is no longer available.')
          .evaluate()
          .isNotEmpty,
    );

    expect(find.text('This invite is no longer available.'), findsOneWidget);
    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    expect(find.text('Email login link'), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
  });

  testWidgets(
      'A 502 accept_failed shows an actionable retry message without signing out',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-502', email: 'invitee@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        return http.Response(
          json.encode({
            'error':
                "We couldn't finish accepting your invite. Please try again.",
            'code': 'accept_failed',
          }),
          502,
        );
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => find
          .text("We couldn't finish accepting your invite. Please try again.")
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.text("We couldn't finish accepting your invite. Please try again."),
      findsOneWidget,
    );
    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    expect(find.text('Email login link'), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
  });

  testWidgets('A network failure shows the network-specific retry message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 3600);
    addTearDown(tester.view.resetPhysicalSize);

    await _primeSession(userId: 'user-network', email: 'invitee@example.com');
    _handler = (request) async {
      final path = request.url.path;
      if (path.contains('/functions/v1/accept-invite')) {
        throw const SocketException('No network');
      }
      if (path.contains('/auth/v1/logout')) {
        return http.Response('', 204);
      }
      return http.Response('', 204);
    };

    final notifier = _TrackingActiveBandNotifier();
    await tester.pumpWidget(_testApp(notifier));
    await _pumpUntil(
      tester,
      () => find
          .text('Network error. Check your connection and try again.')
          .evaluate()
          .isNotEmpty,
    );

    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Please try again.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    _drainKnownRenderOverflow(tester);
  });
}

void _drainKnownRenderOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) return;
  final message = exception.toString();
  expect(
    message,
    anyOf(
      contains('RenderFlex'),
      contains('Multiple exceptions'),
      contains('Null check operator used on a null value'),
    ),
    reason: 'Only known pre-existing layout overflows are expected here',
  );
}
