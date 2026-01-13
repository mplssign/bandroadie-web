import 'package:flutter_test/flutter_test.dart';

import 'package:bandroadie/app/constants/app_constants.dart';
import 'package:bandroadie/features/feedback/bug_report_email_service.dart';

// ============================================================================
// BUG REPORT EMAIL TESTS
// Regression tests to ensure bug reports are sent to the correct email address.
// ============================================================================

void main() {
  group('Bug Report Email Configuration', () {
    test('kSupportEmail is set to the correct address', () {
      // The support email should be hello@bandroadie.com
      // If this test fails, someone changed the email address - verify this was intentional
      expect(kSupportEmail, equals('hello@bandroadie.com'));
    });

    test('BugReportEmailService uses kSupportEmail', () {
      // The service should use the centralized constant
      // This ensures bug reports go to the correct address
      expect(BugReportEmailService.recipientEmail, equals(kSupportEmail));
    });

    test('kSupportEmail is a valid email format', () {
      // Basic validation that it looks like an email
      expect(kSupportEmail.contains('@'), isTrue);
      expect(kSupportEmail.contains('.'), isTrue);
      expect(kSupportEmail.startsWith('@'), isFalse);
      expect(kSupportEmail.endsWith('@'), isFalse);
    });

    test('kSupportEmail uses bandroadie.com domain', () {
      // Ensure we're using our own domain for official support
      expect(kSupportEmail.endsWith('@bandroadie.com'), isTrue);
    });
  });

  group('Bug Report Email Recipient Consistency', () {
    // IMPORTANT: The edge function (supabase/functions/send-bug-report/index.ts)
    // has its own RECIPIENT_EMAIL constant that must match kSupportEmail.
    // This test documents that requirement - manual verification is needed
    // when changing the support email.
    test('documentation: edge function must use same email', () {
      // This is a documentation test - it always passes but reminds developers
      // that the TypeScript edge function must be updated in sync.
      //
      // When changing kSupportEmail, also update:
      //   supabase/functions/send-bug-report/index.ts
      //   const RECIPIENT_EMAIL = "hello@bandroadie.com";
      //
      expect(true, isTrue);
    });
  });
}
