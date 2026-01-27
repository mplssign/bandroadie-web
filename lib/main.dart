import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/services/app_version_service.dart';
import 'app/services/deep_link_service.dart';
import 'app/supabase_config.dart';
import 'app/theme/app_animations.dart';
import 'app/theme/app_theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_confirm_screen.dart';
import 'features/landing/landing_page.dart';
import 'features/legal/privacy_policy_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path-based URLs instead of hash-based URLs on web
  // This allows /app to work instead of requiring /#/app
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // Lock app to portrait mode only
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Initialize app version service
  await AppVersionService.init();

  // Load .env file (silently fails if not present)
  await loadEnvConfig();

  // Validate credentials - returns error message if missing
  final configError = validateSupabaseConfig();
  if (configError != null) {
    // Show error UI instead of crashing
    runApp(ConfigErrorApp(errorMessage: configError));
    return;
  }

  // Initialize Supabase with PKCE auth flow for magic links
  // We handle deep links manually via DeepLinkService to support all app states:
  // - App launched from link (cold start)
  // - App resumed from background via link
  // - App already open when link tapped
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      // Web uses implicit flow (simpler, works better with email links)
      // Native uses PKCE (more secure for deep links)
      authFlowType: kIsWeb ? AuthFlowType.implicit : AuthFlowType.pkce,
      // On web: enable auto-detection so Supabase handles session from URL
      // On native: disable it - we handle deep links manually for iPad/background support
      detectSessionInUri: kIsWeb,
    ),
  );

  // Initialize deep link service for magic link handling in all app states
  // This must be after Supabase.initialize() but before runApp()
  await DeepLinkService.instance.initialize();

  // Create provider container and set it on DeepLinkService
  // This allows DeepLinkService to notify the auth provider of session changes
  final container = ProviderContainer();
  DeepLinkService.instance.setContainer(container);

  // Wrap app with Riverpod for state management using the same container
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const BandRoadieApp(),
    ),
  );
}

class BandRoadieApp extends StatelessWidget {
  const BandRoadieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BandRoadie',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      // Disable device text scaling - use fixed font sizes
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '');

        // Landing page at root (only on web)
        if (uri.path == '/' && kIsWeb) {
          return fadeSlideRoute(page: const LandingPage(), settings: settings);
        }

        // Web app at /app (or default on mobile)
        if (uri.path == '/app' || (uri.path == '/' && !kIsWeb)) {
          return fadeSlideRoute(page: const AuthGate(), settings: settings);
        }

        if (uri.path == '/privacy') {
          // Use custom fade+slide transition for all routes
          return fadeSlideRoute(
            page: const PrivacyPolicyScreen(),
            settings: settings,
          );
        }
        // Legacy /invite route - redirect to AuthGate
        // Invites are now handled automatically when user logs in
        if (uri.path == '/invite') {
          return fadeSlideRoute(page: const AuthGate(), settings: settings);
        }
        if (uri.path == '/auth/confirm') {
          final tokenHash = uri.queryParameters['token_hash'];
          final code = uri.queryParameters['code'];
          final type = uri.queryParameters['type'];
          return fadeSlideRoute(
            page: AuthConfirmScreen(
              tokenHash: tokenHash,
              code: code,
              type: type,
            ),
            settings: settings,
          );
        }
        // Default: Landing page on web, AuthGate on mobile
        return fadeSlideRoute(
          page: kIsWeb ? const LandingPage() : const AuthGate(),
          settings: settings,
        );
      },
      // Fallback for web deep links
      onUnknownRoute: (settings) => fadeSlideRoute(
        page: kIsWeb ? const LandingPage() : const AuthGate(),
        settings: settings,
      ),
    );
  }
}

// ============================================================================
// CONFIG ERROR APP
// Shown when Supabase credentials are missing. Friendly error UI.
// ============================================================================

class ConfigErrorApp extends StatelessWidget {
  final String errorMessage;

  const ConfigErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BandRoadie - Configuration Error',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Error icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.settings_outlined,
                      size: 40,
                      color: Color(0xFFF43F5E),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Configuration Missing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The roadie can\'t find the venue address.\nCheck your .env file or launch config.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  // Technical details
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        errorMessage,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
