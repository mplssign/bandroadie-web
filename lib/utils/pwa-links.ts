/**
 * PWA Magic Link Utilities
 * Handles PWA-specific link generation and routing
 */

interface PWALinkOptions {
  url: string;
  fallbackUrl?: string;
  preferPWA?: boolean;
}

/**
 * Generates PWA-aware magic link HTML for emails
 */
export function generatePWAMagicLinkHTML(options: PWALinkOptions): string {
  const { url, preferPWA = true } = options;
  
  const pwaUrl = new URL(url);
  if (preferPWA) {
    pwaUrl.searchParams.set('pwa_preferred', '1');
  }
  
  return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Sign in to Band Roadie</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background-color: #f8f9fa; border-radius: 8px; padding: 30px; margin: 20px 0;">
          <h1 style="color: #000; margin: 0 0 20px 0; font-size: 24px;">Sign in to Band Roadie</h1>
          <p style="margin: 0 0 20px 0; font-size: 16px;">Click the button below to sign in to your account:</p>
          <div style="text-align: center; margin: 30px 0;">
            <a
              href="${pwaUrl.toString()}"
              style="display: inline-block; background-color: #ffffff; color: #000000; text-decoration: none; padding: 12px 30px; border-radius: 6px; font-weight: 600; font-size: 16px; border: 2px solid #000000;">
              Sign In to Band Roadie
            </a>
          </div>
          <p style="margin: 0 0 20px 0; font-size: 14px; color: #666;">
            If the button above does not work, copy and paste this link into your browser:
          </p>
          <p style="margin: 0 0 20px 0; font-size: 12px; color: #666; word-break: break-all; background-color: #f0f0f0; padding: 10px; border-radius: 4px;">
            <a href="${pwaUrl.toString()}" style="color: #000000; text-decoration: none;">${pwaUrl.toString()}</a>
          </p>
          <p style="margin: 20px 0 0 0; font-size: 14px; color: #666;">
            This link will expire in 1 hour. If you didn't request this email, you can safely ignore it.
          </p>
        </div>
        <p style="font-size: 12px; color: #999; text-align: center; margin-top: 20px;">
          Band Roadie - Your band management tool
        </p>
        
        <!-- PWA Launch Script -->
        <script>
          // If this email is opened in a PWA-capable browser, try to direct to the PWA
          (function() {
            // Check if running in PWA mode
            const isPWA = window.matchMedia('(display-mode: standalone)').matches || 
                         ('standalone' in window.navigator && window.navigator.standalone === true);
            
            if (isPWA) {
              // Already in PWA, enhance the link behavior
              const links = document.querySelectorAll('a[href*="pwa_preferred"]');
              links.forEach(link => {
                link.addEventListener('click', function(e) {
                  e.preventDefault();
                  // Use same window navigation to stay in PWA
                  window.location.href = this.href;
                });
              });
            }
          })();
        </script>
      </body>
    </html>
  `;
}

/**
 * Creates intent URLs for Android PWA launch
 */
export function createAndroidIntentURL(webUrl: string, packageName?: string): string {
  const intentUrl = new URL('intent://');
  intentUrl.pathname = new URL(webUrl).pathname;
  intentUrl.searchParams.set('url', webUrl);
  
  const intentParams = new URLSearchParams();
  intentParams.set('action', 'android.intent.action.VIEW');
  intentParams.set('category', 'android.intent.category.BROWSABLE');
  if (packageName) {
    intentParams.set('package', packageName);
  }
  intentParams.set('S.browser_fallback_url', webUrl);
  
  return `intent:${intentUrl.toString()}#Intent;${intentParams.toString()};end`;
}

/**
 * Creates iOS universal link for PWA launch
 */
export function createIOSUniversalLink(webUrl: string, appScheme?: string): string {
  if (appScheme) {
    return `${appScheme}://${new URL(webUrl).pathname}${new URL(webUrl).search}`;
  }
  return webUrl; // Fallback to web URL
}

/**
 * Detects user agent and creates appropriate PWA link
 */
export function createPWAAwareLink(webUrl: string, userAgent?: string): string {
  if (!userAgent) {
    return webUrl;
  }
  
  const isAndroid = /Android/i.test(userAgent);
  const isIOS = /iPhone|iPad|iPod/i.test(userAgent);
  
  if (isAndroid) {
    // For Android, we rely on the manifest.json capture_links
    return webUrl;
  }
  
  if (isIOS) {
    // For iOS, we rely on the manifest.json and smart app banners
    return webUrl;
  }
  
  return webUrl;
}