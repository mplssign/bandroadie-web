import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

export interface EmailOptions {
  to: string | string[];
  subject: string;
  html: string;
  from?: string;
}

export async function sendEmail({ to, subject, html, from }: EmailOptions) {
  const startTime = Date.now();

  // Log configuration check - always log in production for debugging
  const apiKeyPresent = !!process.env.RESEND_API_KEY;
  const fromAddress =
    from || process.env.RESEND_FROM_EMAIL || 'Band Roadie <noreply@bandroadie.com>';

  if (!apiKeyPresent) {
    console.error('[email.send] CRITICAL: RESEND_API_KEY is not set in environment variables!');
    return {
      success: false,
      error: new Error('RESEND_API_KEY environment variable is not configured'),
    };
  }

  console.log(
    `[email.send] Config check - API key: present, from: ${fromAddress}, to: ${Array.isArray(to) ? to.join(', ') : to}`,
  );

  try {
    const { data, error } = await resend.emails.send({
      from: fromAddress,
      to: Array.isArray(to) ? to : [to],
      subject,
      html,
    });

    const elapsed = Date.now() - startTime;

    if (error) {
      console.error(`[email.send] ERROR (${elapsed}ms):`, JSON.stringify(error, null, 2));
      return { success: false, error };
    }

    if (process.env.NODE_ENV !== 'production') {
      console.log(
        `[email.send] SUCCESS (${elapsed}ms) - ID: ${data?.id || 'unknown'}, to: ${Array.isArray(to) ? to.join(', ') : to}`,
      );
    } else {
      // Log success in production too (helpful for debugging)
      console.log(`[email.send] SUCCESS (${elapsed}ms) - ID: ${data?.id || 'unknown'}`);
    }

    return { success: true, data };
  } catch (error) {
    const elapsed = Date.now() - startTime;
    console.error(`[email.send] EXCEPTION (${elapsed}ms):`, error);

    // Log more details about the error
    if (error instanceof Error) {
      console.error(`[email.send] Error message: ${error.message}`);
      console.error(`[email.send] Error stack: ${error.stack}`);
    }

    return { success: false, error };
  }
}
