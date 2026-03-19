import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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
import 'features/auth/invite_screen.dart';
import 'features/landing/landing_page.dart';
import 'features/legal/privacy_policy_screen.dart';
import 'features/setlists/tuning/tuning_helpers.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/utils/timezone_helper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database for local time display conversion
  TimezoneHelper.initialize();

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

  // Initialize Firebase for push notifications
  // Web uses explicit FirebaseOptions (no google-services.json on web)
  // iOS/Android use native config files via Firebase.initializeApp()
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyD3nIWOdtwNuSkggGs_4Du_rsfvsd7qHxo',
          authDomain: 'bandroadie-65b18.firebaseapp.com',
          projectId: 'bandroadie-65b18',
          storageBucket: 'bandroadie-65b18.firebasestorage.app',
          messagingSenderId: '119100589120',
          appId: '1:119100589120:web:efcfb0cdf1501488c3cba5',
          measurementId: 'G-QFC8JXHKDC',
        ),
      );
    } else if (Platform.isIOS || Platform.isAndroid) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // Silently ignore Firebase init errors on unsupported platforms
    debugPrint('[Main] Firebase init skipped: $e');
  }

  // Initialize deep link service for magic link handling in all app states
  // This must be after Supabase.initialize() but before runApp()
  await DeepLinkService.instance.initialize();

  // Initialize custom tuning cache for displaying custom tuning names on badges
  // This runs async in the background, doesn't block app startup
  refreshCustomTuningCache();

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

/// Returns true if the web app is running on the marketing domain (bandroadie.com).
/// On app.bandroadie.com or non-web platforms, returns false.
bool _isMarketingHost() {
  if (!kIsWeb) return false;
  // ignore: avoid_web_libraries_in_flutter
  final host = Uri.base.host;
  return host == 'bandroadie.com' || host == 'www.bandroadie.com';
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

        // On web, check hostname to decide landing vs app
        if (uri.path == '/' || uri.path == '/app') {
          if (kIsWeb && _isMarketingHost()) {
            return fadeSlideRoute(
                page: const LandingPage(), settings: settings);
          }
          return fadeSlideRoute(page: const AuthGate(), settings: settings);
        }

        if (uri.path == '/privacy') {
          // Use custom fade+slide transition for all routes
          return fadeSlideRoute(
            page: const PrivacyPolicyScreen(),
            settings: settings,
          );
        }
        // Invite route - handles band invitations with token
        if (uri.path == '/invite') {
          final token = uri.queryParameters['token'];
          return fadeSlideRoute(
            page: InviteScreen(token: token),
            settings: settings,
          );
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
        // Default: landing page on marketing host, AuthGate otherwise
        if (kIsWeb && _isMarketingHost()) {
          return fadeSlideRoute(page: const LandingPage(), settings: settings);
        }
        return fadeSlideRoute(
          page: const AuthGate(),
          settings: settings,
        );
      },
      // Fallback for unknown routes
      onUnknownRoute: (settings) => fadeSlideRoute(
        page: kIsWeb && _isMarketingHost()
            ? const LandingPage()
            : const AuthGate(),
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
        backgroundColor: AppColors.background,
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
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.settings,
                      size: 40,
                      color: AppColors.primary,
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
                    style:
                        TextStyle(color: AppColors.textSecondary, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  // Technical details
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.surfaceOverlay),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        errorMessage,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
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
