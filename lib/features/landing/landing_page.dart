import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/scroll_animated_widget.dart';
import 'widgets/hero_section.dart';
import 'widgets/features_section.dart';
import 'widgets/value_section.dart';
import 'widgets/screenshots_section.dart';
import 'widgets/download_section.dart';
import 'widgets/footer_section.dart';

/// Landing page for BandRoadie - Zenity-inspired design
/// 
/// Sections:
/// 1. Hero with app name, tagline, and CTAs
/// 2. Features grid (Rehearsals, Gigs, Calendar, Setlists)
/// 3. Value proposition (Why BandRoadie)
/// 4. Screenshots carousel
/// 5. Download CTAs
/// 6. Footer with legal links
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Small delay to ensure smooth rendering
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.offset > 400 && !_showScrollToTop) {
      setState(() => _showScrollToTop = true);
    } else if (_scrollController.offset <= 400 && _showScrollToTop) {
      setState(() => _showScrollToTop = false);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: !_isLoaded
          ? const Center(
              child: SizedBox.shrink(), // Invisible until loaded
            )
          : Stack(
        children: [
          // Main content
          SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              children: [
                const HeroSection(),
                ScrollAnimatedWidget(
                  offset: const Offset(0, 80),
                  child: const FeaturesSection(),
                ),
                ScrollAnimatedWidget(
                  offset: const Offset(0, 80),
                  child: const ValueSection(),
                ),
                ScrollAnimatedWidget(
                  offset: const Offset(0, 80),
                  child: const ScreenshotsSection(),
                ),
                ScrollAnimatedWidget(
                  offset: const Offset(0, 80),
                  child: const DownloadSection(),
                ),
                const FooterSection(),
              ],
            ),
          ),
          
          // Scroll to top FAB
          if (_showScrollToTop)
            Positioned(
              right: 24,
              bottom: 24,
              child: FloatingActionButton(
                onPressed: _scrollToTop,
                backgroundColor: AppColors.accent,
                child: const Icon(Icons.arrow_upward, color: Colors.black),
              ),
            ),
        ],
      ),
    );
  }
}
