import { APP_URL } from '@/lib/constants';

export function getInviteEmailHtml(
  bandName: string,
  inviterName: string,
): string {
  // Use the main app URL - user will log in normally and be auto-added to the band
  const loginUrl = APP_URL;

  return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>You're invited to join ${bandName}</title>
        <style>
          body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            line-height: 1.6;
            color: #fafafa;
            background-color: #0a0a0a;
          }
          .container {
            max-width: 600px;
            margin: 0 auto;
            padding: 40px 20px;
          }
          .card {
            background-color: #141414;
            border-radius: 12px;
            padding: 40px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
          }
          h1 {
            color: #fafafa;
            font-size: 28px;
            margin: 0 0 20px;
            text-align: center;
          }
          .logo {
            text-align: center;
            margin-bottom: 30px;
            font-size: 24px;
            font-weight: bold;
            color: #dc2626;
          }
          .band-name {
            color: #dc2626;
            font-weight: bold;
          }
          p {
            color: #a3a3a3;
            margin: 0 0 20px;
            text-align: center;
          }
          .highlight-box {
            background-color: #1a1a1a;
            border-left: 4px solid #dc2626;
            border-radius: 0 8px 8px 0;
            padding: 16px 20px;
            margin: 24px 0;
          }
          .highlight-box p {
            margin: 0;
            text-align: left;
            color: #fafafa;
          }
          .button {
            display: inline-block;
            background-color: #dc2626;
            color: #fafafa !important;
            text-decoration: none;
            padding: 14px 32px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 16px;
            text-align: center;
            margin: 20px auto;
            display: block;
            width: fit-content;
          }
          .features {
            background-color: #1a1a1a;
            border-radius: 8px;
            padding: 20px;
            margin: 30px 0;
          }
          .features h2 {
            color: #fafafa;
            font-size: 18px;
            margin: 0 0 16px;
          }
          .features ul {
            list-style: none;
            padding: 0;
            margin: 0;
          }
          .features li {
            color: #a3a3a3;
            padding: 8px 0;
            padding-left: 24px;
            position: relative;
          }
          .features li:before {
            content: "✓";
            color: #dc2626;
            position: absolute;
            left: 0;
            font-weight: bold;
          }
          .footer {
            text-align: center;
            margin-top: 40px;
            color: #737373;
            font-size: 14px;
          }
          .footer a {
            color: #dc2626;
            text-decoration: none;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="card">
            <div class="logo">🎸 Band Roadie</div>
            <h1>You're invited!</h1>
            <p style="font-size: 18px;">
              ${inviterName} has invited you to join <span class="band-name">${bandName}</span> on Band Roadie
            </p>
            
            <div class="highlight-box">
              <p>📧 <strong>Just log in with this email address</strong> to automatically join the band. No special link needed!</p>
            </div>
            
            <a href="${loginUrl}" style="display:inline-block;background-color:#dc2626;color:#fafafa!important;text-decoration:none;padding:14px 32px;border-radius:8px;font-weight:600;font-size:16px;text-align:center;margin:20px auto;display:block;width:fit-content;" target="_blank" rel="noopener">Open Band Roadie</a>
            
            <div class="features">
              <h2>With Band Roadie, you can:</h2>
              <ul>
                <li>Manage rehearsals and gigs</li>
                <li>Create and share setlists</li>
                <li>Coordinate with band members</li>
                <li>Track upcoming events</li>
                <li>Access everything from any device</li>
              </ul>
            </div>
            
            <div class="footer">
              <p>Visit Band Roadie at:</p>
              <a href="${loginUrl}">${loginUrl}</a>
              <p style="margin-top: 20px;">© 2025 Band Roadie. All rights reserved.</p>
            </div>
          </div>
        </div>
      </body>
    </html>
  `;
}
