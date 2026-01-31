import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/design_tokens.dart';

/// Community section promoting r/bandroadie subreddit
class CommunitySection extends StatelessWidget {
  const CommunitySection({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    final screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 80,
        vertical: isMobile ? 60 : 100,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1a0f2e), // Deep purple
            const Color(0xFF0f1a2e), // Deep blue
            const Color(0xFF0a1428), // Darker blue
            const Color(0xFF1a0f2e), // Back to deep purple
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ),
      ),
      child: Column(
        children: [
          // Section title
          Text(
            'Join the BandRoadie Community',
            textAlign: TextAlign.center,
            style: AppTextStyles.title3.copyWith(
              fontSize: isMobile ? 32 : 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Connect with other bands, share ideas, and help shape the future of BandRoadie',
            textAlign: TextAlign.center,
            style: AppTextStyles.callout.copyWith(
              fontSize: 18,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // Community points - 2x2 grid until mobile, 1-column on mobile
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: !isMobile
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column - 2 items
                      Expanded(
                        child: Column(
                          children: [
                            _CommunityPoint(
                              icon: Icons.forum_rounded,
                              text: 'General discussion around the app',
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 24),
                            _CommunityPoint(
                              icon: Icons.tips_and_updates_rounded,
                              text:
                                  'Tips & tricks for getting the most out of BandRoadie',
                              isMobile: isMobile,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                      // Right column - 2 items
                      Expanded(
                        child: Column(
                          children: [
                            _CommunityPoint(
                              icon: Icons.lightbulb_rounded,
                              text: 'Feature ideas & feedback',
                              isMobile: isMobile,
                            ),
                            const SizedBox(height: 24),
                            _CommunityPoint(
                              icon: Icons.support_agent_rounded,
                              text: 'App support and troubleshooting',
                              isMobile: isMobile,
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _CommunityPoint(
                        icon: Icons.forum_rounded,
                        text: 'General discussion around the app',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 20),
                      _CommunityPoint(
                        icon: Icons.lightbulb_rounded,
                        text: 'Feature ideas & feedback',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 20),
                      _CommunityPoint(
                        icon: Icons.tips_and_updates_rounded,
                        text:
                            'Tips & tricks for getting the most out of BandRoadie',
                        isMobile: isMobile,
                      ),
                      const SizedBox(height: 20),
                      _CommunityPoint(
                        icon: Icons.support_agent_rounded,
                        text: 'App support and troubleshooting',
                        isMobile: isMobile,
                      ),
                    ],
                  ),
          ),
          SizedBox(height: isMobile ? 40 : 60),

          // CTA Button
          _RedditCTAButton(isMobile: isMobile),
        ],
      ),
    );
  }
}

class _CommunityPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isMobile;

  const _CommunityPoint({
    required this.icon,
    required this.text,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(
              0xFF3d5af1,
            ).withValues(alpha: 0.2), // Blue accent
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF3d5af1).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: const Color(0xFF6c8aff),
          ), // Light blue
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: AppTextStyles.callout.copyWith(
                fontSize: isMobile ? 16 : 17,
                color: Colors.white.withValues(alpha: 0.95),
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RedditCTAButton extends StatefulWidget {
  final bool isMobile;

  const _RedditCTAButton({required this.isMobile});

  @override
  State<_RedditCTAButton> createState() => _RedditCTAButtonState();
}

class _RedditCTAButtonState extends State<_RedditCTAButton> {
  bool _isHovered = false;

  Future<void> _launchReddit() async {
    final uri = Uri.parse('https://www.reddit.com/r/bandroadie');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: Matrix4.translationValues(0, _isHovered ? -4 : 0, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _launchReddit,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isMobile ? 32 : 48,
                vertical: widget.isMobile ? 16 : 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF3d5af1), // Blue
                    const Color(0xFF5a3df1), // Purple-blue
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: const Color(0xFF3d5af1).withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: const Color(0xFF3d5af1).withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.reddit,
                    size: widget.isMobile ? 24 : 28,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Visit r/bandroadie',
                    style: TextStyle(
                      fontSize: widget.isMobile ? 18 : 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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
