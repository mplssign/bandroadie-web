import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import '../../shared/widgets/animated_logo.dart';

/// Privacy Policy screen - accessible without authentication at /privacy
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  color: AppColors.textPrimary,
                ),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const BandRoadieLogo(height: 32),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle('Privacy Policy for Band Roadie'),
            _buildSubtitle('Effective Date: January 2026'),
            const SizedBox(height: 16),
            _buildParagraph(
              'Band Roadie ("we," "our," or "us") respects your privacy. This Privacy Policy explains how information is collected, used, and protected when you use the Band Roadie mobile application (the "App").',
            ),
            _buildDivider(),

            // Information We Collect
            _buildSectionHeader('Information We Collect'),
            _buildParagraph(
              'Band Roadie collects only the information necessary to provide core app functionality.',
            ),
            const SizedBox(height: 12),
            _buildSubheader('Information You Provide'),
            _buildBullet(
              'Account information (such as email address) used for authentication',
            ),
            _buildBullet(
              'User-generated content, including band names, gigs, rehearsals, setlists, and related details',
            ),
            const SizedBox(height: 12),
            _buildSubheader('Automatically Collected Information'),
            _buildBullet(
              'Basic technical information required for the app to function properly (such as device type and operating system version)',
            ),
            const SizedBox(height: 12),
            _buildParagraph(
              'Band Roadie does not collect sensitive personal data such as payment information, precise location, contacts, or health data.',
            ),
            _buildDivider(),

            // How We Use Information
            _buildSectionHeader('How We Use Information'),
            _buildParagraph('We use collected information to:'),
            _buildBullet('Authenticate users and provide secure access'),
            _buildBullet('Enable collaboration between band members'),
            _buildBullet('Store and display gigs, rehearsals, and setlists'),
            _buildBullet('Maintain and improve app functionality'),
            const SizedBox(height: 12),
            _buildParagraph('We do not sell or rent user data.'),
            _buildDivider(),

            // Data Sharing
            _buildSectionHeader('Data Sharing'),
            _buildParagraph(
              'Band Roadie does not share personal information with third parties for advertising or marketing purposes.',
            ),
            const SizedBox(height: 12),
            _buildParagraph('Information may be shared only when:'),
            _buildBullet('Required to operate core app services'),
            _buildBullet('Required by law or legal process'),
            _buildDivider(),

            // Data Retention
            _buildSectionHeader('Data Retention'),
            _buildParagraph(
              'We retain user information only as long as necessary to provide the app\'s services.',
            ),
            _buildParagraph(
              'Users may request deletion of their account and associated data.',
            ),
            _buildDivider(),

            // Data Security
            _buildSectionHeader('Data Security'),
            _buildParagraph(
              'We take reasonable measures to protect user information using standard security practices, including encrypted connections and access controls.',
            ),
            const SizedBox(height: 12),
            _buildParagraph(
              'No method of transmission or storage is 100% secure, but we strive to protect your data.',
            ),
            _buildDivider(),

            // Children's Privacy
            _buildSectionHeader('Children\'s Privacy'),
            _buildParagraph(
              'Band Roadie is not intended for children under the age of 13.',
            ),
            _buildParagraph(
              'We do not knowingly collect personal information from children.',
            ),
            _buildDivider(),

            // Your Choices
            _buildSectionHeader('Your Choices'),
            _buildParagraph('You may:'),
            _buildBullet('Access and update your information within the app'),
            _buildBullet(
              'Request deletion of your account and associated data',
            ),
            _buildDivider(),

            // Changes to This Policy
            _buildSectionHeader('Changes to This Policy'),
            _buildParagraph(
              'This Privacy Policy may be updated from time to time. Any changes will be reflected by updating the effective date.',
            ),
            _buildDivider(),

            // Contact
            _buildSectionHeader('Contact'),
            _buildParagraph(
              'If you have questions about this Privacy Policy, please contact:',
            ),
            const SizedBox(height: 8),
            _buildParagraph('Email: hello@bandroadie.com'),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }

  Widget _buildSubtitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }

  Widget _buildSubheader(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              height: 1.5,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Divider(color: AppColors.borderMuted, height: 1),
    );
  }
}
