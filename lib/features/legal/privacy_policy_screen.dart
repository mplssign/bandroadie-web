import 'package:flutter/material.dart';
import 'package:bandroadie/app/theme/design_tokens.dart';

import 'package:bandroadie/app/theme/brand_colors.dart';
import '../../shared/widgets/animated_logo.dart';
import 'package:bandroadie/app/theme/app_icons.dart';

/// Privacy Policy screen - accessible without authentication at /privacy
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: Icon(
                  AppIcons.arrowLeft,
                  color: context.colors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const BandRoadieLogo(
          height: 32,
          asset: 'assets/images/bandroadie_logo_rose_tag.svg',
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle(context, 'Privacy Policy for Band Roadie'),
            _buildSubtitle(context, 'Effective Date: January 2026'),
            const SizedBox(height: 16),
            _buildParagraph(
              context,
              'Band Roadie ("we," "our," or "us") respects your privacy. This Privacy Policy explains how information is collected, used, and protected when you use the Band Roadie mobile application (the "App").',
            ),
            _buildDivider(context),

            // Information We Collect
            _buildSectionHeader(context, 'Information We Collect'),
            _buildParagraph(
              context,
              'Band Roadie collects only the information necessary to provide core app functionality.',
            ),
            const SizedBox(height: 12),
            _buildSubheader(context, 'Information You Provide'),
            _buildBullet(
              context,
              'Account information (such as email address) used for authentication',
            ),
            _buildBullet(
              context,
              'User-generated content, including band names, gigs, rehearsals, setlists, and related details',
            ),
            const SizedBox(height: 12),
            _buildSubheader(context, 'Automatically Collected Information'),
            _buildBullet(
              context,
              'Basic technical information required for the app to function properly (such as device type and operating system version)',
            ),
            const SizedBox(height: 12),
            _buildParagraph(
              context,
              'Band Roadie does not collect sensitive personal data such as payment information, precise location, contacts, or health data.',
            ),
            _buildDivider(context),

            // How We Use Information
            _buildSectionHeader(context, 'How We Use Information'),
            _buildParagraph(context, 'We use collected information to:'),
            _buildBullet(
                context, 'Authenticate users and provide secure access'),
            _buildBullet(context, 'Enable collaboration between band members'),
            _buildBullet(
                context, 'Store and display gigs, rehearsals, and setlists'),
            _buildBullet(context, 'Maintain and improve app functionality'),
            const SizedBox(height: 12),
            _buildParagraph(context, 'We do not sell or rent user data.'),
            _buildDivider(context),

            // Data Sharing
            _buildSectionHeader(context, 'Data Sharing'),
            _buildParagraph(
              context,
              'Band Roadie does not share personal information with third parties for advertising or marketing purposes.',
            ),
            const SizedBox(height: 12),
            _buildParagraph(context, 'Information may be shared only when:'),
            _buildBullet(context, 'Required to operate core app services'),
            _buildBullet(context, 'Required by law or legal process'),
            const SizedBox(height: 12),
            _buildSubheader(context, 'Third-Party Data Providers'),
            _buildParagraph(context,
                "BandRoadie uses third-party services to help build your band's song catalog. When you look up a song, we may send the song title and artist name to GetSongBPM (getsongbpm.com) to retrieve tempo (BPM) and key information for that song."),
            _buildParagraph(
                context, 'Data from GetSongBPM: https://getsongbpm.com/.'),
            _buildDivider(context),

            // Data Retention
            _buildSectionHeader(context, 'Data Retention'),
            _buildParagraph(
              context,
              'We retain user information only as long as necessary to provide the app\'s services.',
            ),
            _buildParagraph(
              context,
              'Users may request deletion of their account and associated data.',
            ),
            _buildDivider(context),

            // Data Security
            _buildSectionHeader(context, 'Data Security'),
            _buildParagraph(
              context,
              'We take reasonable measures to protect user information using standard security practices, including encrypted connections and access controls.',
            ),
            const SizedBox(height: 12),
            _buildParagraph(
              context,
              'No method of transmission or storage is 100% secure, but we strive to protect your data.',
            ),
            _buildDivider(context),

            // Children's Privacy
            _buildSectionHeader(context, 'Children\'s Privacy'),
            _buildParagraph(
              context,
              'Band Roadie is not intended for children under the age of 13.',
            ),
            _buildParagraph(
              context,
              'We do not knowingly collect personal information from children.',
            ),
            _buildDivider(context),

            // Your Choices
            _buildSectionHeader(context, 'Your Choices'),
            _buildParagraph(context, 'You may:'),
            _buildBullet(
                context, 'Access and update your information within the app'),
            _buildBullet(
              context,
              'Request deletion of your account and associated data',
            ),
            _buildDivider(context),

            // Changes to This Policy
            _buildSectionHeader(context, 'Changes to This Policy'),
            _buildParagraph(
              context,
              'This Privacy Policy may be updated from time to time. Any changes will be reflected by updating the effective date.',
            ),
            _buildDivider(context),

            // Contact
            _buildSectionHeader(context, 'Contact'),
            _buildParagraph(
              context,
              'If you have questions about this Privacy Policy, please contact:',
            ),
            const SizedBox(height: 8),
            _buildParagraph(context, 'Email: hello@bandroadie.com'),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: AppFontSizes.modalTitle,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: AppFontSizes.title,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildSubheader(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParagraph(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: AppFontSizes.subhead,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: AppFontSizes.subhead,
              height: 1.5,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: AppFontSizes.subhead,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(color: context.colors.border, height: 1),
    );
  }
}
