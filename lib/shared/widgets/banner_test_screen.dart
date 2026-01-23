import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../utils/platform_detection.dart';
import '../utils/web_storage.dart';
import '../utils/banner_debug.dart';
import '../../app/theme/design_tokens.dart';

/// A debug screen to test native app banner detection.
/// Remove this file before production or add route protection.
class BannerTestScreen extends StatefulWidget {
  const BannerTestScreen({super.key});

  @override
  State<BannerTestScreen> createState() => _BannerTestScreenState();
}

class _BannerTestScreenState extends State<BannerTestScreen> {
  Map<String, dynamic>? _debugInfo;

  @override
  void initState() {
    super.initState();
    _loadDebugInfo();
  }

  void _loadDebugInfo() {
    if (kIsWeb) {
      setState(() {
        _debugInfo = BannerDebugInfo.info;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banner Debug'),
        backgroundColor: AppColors.appBarBg,
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.space16),
        children: [
          _buildHeader(),
          const SizedBox(height: Spacing.space24),
          _buildPlatformInfo(),
          const SizedBox(height: Spacing.space24),
          _buildStorageInfo(),
          const SizedBox(height: Spacing.space24),
          _buildActions(),
          const SizedBox(height: Spacing.space24),
          _buildRawDebugInfo(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: AppColors.cardBgElevated,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎸 Native App Banner Debugger',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.space8),
            Text(
              'Use this screen to debug why the banner is or isn\'t showing.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformInfo() {
    if (!kIsWeb) {
      return _buildInfoCard(
        '❌ Not on Web',
        'This app is running on a native platform, not web.',
        Colors.red,
      );
    }

    final shouldShow = isMobileWeb && !isStandalone && !dismissedAppBanner;

    return Column(
      children: [
        _buildInfoCard(
          shouldShow ? '✅ Banner Should Show' : '❌ Banner Should NOT Show',
          shouldShow
              ? 'All conditions met for showing the banner.'
              : 'One or more conditions not met.',
          shouldShow ? Colors.green : Colors.red,
        ),
        const SizedBox(height: Spacing.space16),
        _buildConditionTile('Is Mobile Web', isMobileWeb),
        _buildConditionTile('Is iOS', isIOS),
        _buildConditionTile('Is Android', isAndroid),
        _buildConditionTile('Is Standalone/PWA', isStandalone, invert: true),
        _buildConditionTile(
          'Banner Dismissed',
          dismissedAppBanner,
          invert: true,
        ),
      ],
    );
  }

  Widget _buildStorageInfo() {
    if (!kIsWeb) return const SizedBox.shrink();

    final dismissedAt = getBannerDismissedAt();

    return Card(
      color: AppColors.cardBgElevated,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'localStorage Info',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.space12),
            _buildKeyValue('Dismissed', dismissedAppBanner ? 'Yes' : 'No'),
            if (dismissedAt != null) ...[
              const SizedBox(height: Spacing.space8),
              _buildKeyValue('Dismissed At', '${dismissedAt.toLocal()}'),
              const SizedBox(height: Spacing.space8),
              _buildKeyValue(
                'Days Ago',
                '${DateTime.now().difference(dismissedAt).inDays}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        ElevatedButton.icon(
          onPressed: () {
            BannerDebugInfo.resetDismissal();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Dismissal reset. Reload app to see banner.'),
              ),
            );
            _loadDebugInfo();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Reset Banner Dismissal'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: Spacing.space12),
        ElevatedButton.icon(
          onPressed: () {
            BannerDebugInfo.forceDismiss();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Banner dismissed. Reset to undo.'),
              ),
            );
            _loadDebugInfo();
          },
          icon: const Icon(Icons.block),
          label: const Text('Force Dismiss Banner'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: Spacing.space12),
        ElevatedButton.icon(
          onPressed: () {
            BannerDebugInfo.printDebugInfo();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Check console for debug info')),
            );
            _loadDebugInfo();
          },
          icon: const Icon(Icons.terminal),
          label: const Text('Print to Console'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blueAccent,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }

  Widget _buildRawDebugInfo() {
    if (!kIsWeb || _debugInfo == null) return const SizedBox.shrink();

    return Card(
      color: AppColors.cardBgElevated,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raw Debug Data',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: Spacing.space12),
            SelectableText(
              _debugInfo.toString(),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String subtitle, Color color) {
    return Card(
      color: AppColors.cardBgElevated,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.space16),
        child: Row(
          children: [
            Icon(
              title.startsWith('✅')
                  ? Icons.check_circle
                  : Icons.cancel_outlined,
              color: color,
              size: 32,
            ),
            const SizedBox(width: Spacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionTile(String label, bool value, {bool invert = false}) {
    final passed = invert ? !value : value;
    return Card(
      color: AppColors.cardBg,
      child: ListTile(
        leading: Icon(
          passed ? Icons.check_circle : Icons.cancel,
          color: passed ? Colors.green : Colors.red,
        ),
        title: Text(
          label,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        trailing: Text(
          value ? 'true' : 'false',
          style: TextStyle(
            color: passed ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildKeyValue(String key, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          key,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
