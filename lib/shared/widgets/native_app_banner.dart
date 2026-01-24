import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/platform_detection.dart';
import '../utils/web_storage.dart';
import '../../app/theme/design_tokens.dart';

/// A dismissible banner that prompts mobile web users to download the native app.
///
/// Shows only on mobile browsers (iOS Safari, Android Chrome), not on desktop
/// or when running as PWA/standalone. Respects user dismissal stored in localStorage.
///
/// Usage:
/// ```dart
/// Scaffold(
///   body: Stack(
///     children: [
///       // Your main content
///       YourContent(),
///       // Banner overlay
///       const NativeAppBanner(),
///     ],
///   ),
/// )
/// ```
class NativeAppBanner extends StatefulWidget {
  /// Delay before showing the banner (default: 4 seconds)
  final Duration delay;

  /// Position of the banner (default: top)
  final BannerPosition position;

  /// Whether to hide on auth pages (login/signup)
  final bool hideOnAuthPages;

  const NativeAppBanner({
    super.key,
    this.delay = const Duration(seconds: 4),
    this.position = BannerPosition.top,
    this.hideOnAuthPages = true,
  });

  @override
  State<NativeAppBanner> createState() => _NativeAppBannerState();
}

class _NativeAppBannerState extends State<NativeAppBanner>
    with SingleTickerProviderStateMixin {
  bool _visible = false;
  bool _shouldShow = false;
  AnimationController? _controller;
  Animation<double>? _slideAnimation;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();

    // Only proceed on web
    if (!kIsWeb) {
      debugPrint('NativeAppBanner: Not on web, skipping');
      return;
    }

    // Check if we should show the banner
    _shouldShow = _checkShouldShow();

    debugPrint('NativeAppBanner: _shouldShow = $_shouldShow');
    debugPrint('NativeAppBanner: isMobileWeb = $isMobileWeb');
    debugPrint('NativeAppBanner: isStandalone = $isStandalone');
    debugPrint('NativeAppBanner: dismissedAppBanner = $dismissedAppBanner');

    if (_shouldShow) {
      // Setup animation
      _controller = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );

      _slideAnimation = CurvedAnimation(
        parent: _controller!,
        curve: Curves.easeOut,
      );

      // Delay appearance
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          debugPrint('NativeAppBanner: Showing banner after delay');
          setState(() => _visible = true);
          _controller?.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  bool _checkShouldShow() {
    // Check platform requirements
    if (!isMobileWeb) return false;
    if (isStandalone) return false;
    if (dismissedAppBanner) return false;

    // Hide on auth pages if configured
    if (widget.hideOnAuthPages) {
      // TODO: Add route checking if needed
      // For now, just show everywhere
    }

    return true;
  }

  void _dismiss() {
    // Animate out
    _controller?.reverse().then((_) {
      if (mounted) {
        setState(() => _visible = false);
      }
    });

    // Persist dismissal
    dismissAppBanner();

    // Optional: Fire analytics event
    // _trackBannerDismissed();
  }

  Future<void> _downloadApp() async {
    // Determine store URL based on platform
    final String storeUrl = isIOS
        ? 'https://apps.apple.com/us/app/band-roadie/id6757283775'
        : 'https://play.google.com/store/apps/details?id=com.bandroadie.app';

    final uri = Uri.parse(storeUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);

      // Optional: Fire analytics event
      // _trackBannerClicked(platform: isIOS ? 'ios' : 'android');
    }

    // Dismiss after click
    _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_shouldShow || !_visible || _slideAnimation == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: widget.position == BannerPosition.top ? 0 : null,
      bottom: widget.position == BannerPosition.bottom ? 0 : null,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.position == BannerPosition.top
              ? const Offset(0, -1)
              : const Offset(0, 1),
          end: Offset.zero,
        ).animate(_slideAnimation!),
        child: SafeArea(
          child: _BannerContent(onDismiss: _dismiss, onDownload: _downloadApp),
        ),
      ),
    );
  }
}

class _BannerContent extends StatelessWidget {
  final VoidCallback onDismiss;
  final VoidCallback onDownload;

  const _BannerContent({required this.onDismiss, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(Spacing.space12),
      decoration: BoxDecoration(
        color: const Color(0xFFF43F5E), // Rose background
        borderRadius: BorderRadius.circular(Spacing.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.space16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title and close button
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Get the full BandRoadie experience',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.black,
                    onPressed: onDismiss,
                    tooltip: 'Don\'t show again',
                  ),
                ],
              ),
              const SizedBox(height: Spacing.space8),
              // Subtitle
              const Text(
                'Faster performance, offline access, and notifications.',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: Spacing.space16),
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDownload,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.space12,
                        ),
                        side: const BorderSide(color: Colors.black, width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            Spacing.buttonRadius,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Download app',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.space12),
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.space16,
                        vertical: Spacing.space12,
                      ),
                    ),
                    child: const Text(
                      'Don\'t show again',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Position of the banner on screen
enum BannerPosition { top, bottom }
