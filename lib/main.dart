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
import 'app/firebase_config.dart';
import 'app/supabase_config.dart';
import 'app/theme/app_animations.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/theme_mode_controller.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/auth_confirm_screen.dart';
import 'features/auth/invite_screen.dart';
import 'features/landing/landing_page.dart';
import 'features/legal/privacy_policy_screen.dart';
import 'features/setlists/tuning/tuning_helpers.dart';
import 'package:bandroadie/app/theme/app_icons.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';
import 'package:bandroadie/app/theme/brand_colors.dart';
import 'package:bandroadie/app/utils/timezone_helper.dart';
import 'shared/widgets/keyboard_aware_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database for local time display conversion
  TimezoneHelper.initialize();

  // Use path-based URLs instead of hash-based URLs on web
  // This allows /app to work instead of requiring /#/app
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await AppVersionService.init();

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
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        // All platforms use PKCE flow for secure token exchange
        // Web: code_verifier stored in localStorage; scanners cannot complete exchange
        // Native: code_verifier stored in device storage; handled via deep links
        authFlowType: AuthFlowType.pkce,
        // On web: enable auto-detection so Supabase handles session from URL
        // On native: disable it - we handle deep links manually for iPad/background support
        detectSessionInUri: kIsWeb,
      ),
    );
  } on FormatException catch (e) {
    debugPrint('[Main] Corrupt session data detected: $e');
    debugPrint('[Main] Clearing local session and reinitializing...');

    // Clear any corrupt session data (local only, doesn't call server)
    // This handles cases where app downgrade or storage corruption breaks session schema
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Ignore errors during cleanup — storage may be completely broken
    }

    // Retry initialization with clean state
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        detectSessionInUri: kIsWeb,
      ),
    );
  }

  // Initialize Firebase for push notifications
  // Web uses explicit FirebaseOptions (no google-services.json on web)
  // iOS/Android use native config files via Firebase.initializeApp()
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(
        options: firebaseWebOptions,
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

class BandRoadieApp extends ConsumerWidget {
  const BandRoadieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'BandRoadie',
      debugShowCheckedModeBanner: false,
      themeMode: ref.watch(themeModeProvider),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      // Disable device text scaling - use fixed font sizes.
      // KeyboardAwareWrapper ensures focused fields scroll above the keyboard.
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: KeyboardAwareWrapper(child: child!),
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
          return fadeSlideRoute(
            page: const PrivacyPolicyScreen(),
            settings: settings,
          );
        }
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
        if (kIsWeb && _isMarketingHost()) {
          return fadeSlideRoute(page: const LandingPage(), settings: settings);
        }
        return fadeSlideRoute(
          page: const AuthGate(),
          settings: settings,
        );
      },
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
        backgroundColor: BrandColors.dark.background,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                      fontSize: AppFontSizes.modalTitle,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The roadie can\'t find the venue address.\nCheck your .env file or launch config.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: BrandColors.dark.textSecondary,
                        fontSize: AppFontSizes.body),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: BrandColors.dark.surface,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: BrandColors.dark.surfaceOverlay),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        errorMessage,
                        style: TextStyle(
                          color: BrandColors.dark.textSecondary,
                          fontSize: AppFontSizes.caption,
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
