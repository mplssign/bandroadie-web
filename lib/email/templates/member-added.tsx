import { APP_URL, APP_NAME } from '@/lib/constants';

export function getBandMemberAddedEmailHtml(
  bandName: string,
  inviterName: string,
  _bandId: string,
) {
  const dashboardUrl = `${APP_URL}/dashboard`;

  return `
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <title>${bandName} on ${APP_NAME}</title>
        <style>
          body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background-color: #0a0a0a;
            color: #fafafa;
          }
          .container {
            max-width: 560px;
            margin: 0 auto;
            padding: 40px 24px;
          }
          .card {
            background-color: #141414;
            border-radius: 16px;
            padding: 40px;
            box-shadow: 0 12px 35px rgba(15, 23, 42, 0.35);
          }
          h1 {
            font-size: 26px;
            margin: 0 0 16px;
            text-align: center;
          }
          p {
            font-size: 16px;
            line-height: 1.6;
            margin: 0 0 18px;
            color: #cbd5f5;
            text-align: center;
          }
          .band {
            color: #f97316;
            font-weight: 600;
          }
          .cta {
            display: inline-block;
            margin: 24px auto 0;
            padding: 12px 32px;
            border-radius: 9999px;
            background: linear-gradient(135deg, #f97316, #ef4444);
            color: #fff !important;
            text-decoration: none;
            font-weight: 600;
            font-size: 16px;
            letter-spacing: 0.01em;
          }
          .footer {
            margin-top: 36px;
            font-size: 13px;
            text-align: center;
            color: #94a3b8;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="card">
            <h1>Welcome to the band!</h1>
            <p>
              ${inviterName} just added you to <span class="band">${bandName}</span> on ${APP_NAME}.
            </p>
            <p>
              Jump into the dashboard to catch up on rehearsals, gigs, and setlists that the band is working on.
            </p>
            <a class="cta" href="${dashboardUrl}">Open Band Roadie</a>
            <div class="footer">
              Need help? Reply to this email and we&apos;ll get you sorted.
            </div>
          </div>
        </div>
      </body>
    </html>
  `;
}
