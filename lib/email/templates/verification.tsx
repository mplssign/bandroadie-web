import { APP_URL } from '@/lib/constants';

export function getVerificationEmailHtml(token: string, isNewUser: boolean = true): string {
  const verifyUrl = `${APP_URL}/verify?token=${token}`;
  const action = isNewUser ? 'Verify your account' : 'Sign in to Band Roadie';
  const greeting = isNewUser ? 'Welcome to Band Roadie!' : 'Welcome back!';
  
  return `
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${action}</title>
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
          p {
            color: #a3a3a3;
            margin: 0 0 20px;
            text-align: center;
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
          .button:hover {
            background-color: #b91c1c;
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
          .divider {
            height: 1px;
            background-color: #262626;
            margin: 30px 0;
          }
          .security-note {
            background-color: #1a1a1a;
            border-radius: 8px;
            padding: 16px;
            margin-top: 20px;
            font-size: 14px;
            color: #a3a3a3;
            text-align: center;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="card">
            <div class="logo">🎸 Band Roadie</div>
            <h1>${greeting}</h1>
            <p>${isNewUser ? 'Click the button below to verify your email and get started.' : 'Click the button below to sign in to your account.'}</p>
            
            <a href="${verifyUrl}" class="button">${action}</a>
            
            <div class="divider"></div>
            
            <div class="security-note">
              This link will expire in 24 hours. If you didn't request this email, you can safely ignore it.
            </div>
            
            <div class="footer">
              <p>Having trouble? Copy and paste this link into your browser:</p>
              <a href="${verifyUrl}">${verifyUrl}</a>
              <p style="margin-top: 20px;">© 2025 Band Roadie. All rights reserved.</p>
            </div>
          </div>
        </div>
      </body>
    </html>
  `;
}
