const logger = require('../utils/logger');
const AppError = require('../utils/AppError');

const RESEND_API_URL = 'https://api.resend.com/emails';

/**
 * Builds the branded HTML email for OTP delivery.
 */
function buildOtpEmailHtml(otp) {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your Verification Code - Maneyindha Marukatte</title>
</head>
<body style="margin: 0; padding: 0; background-color: #FAF7F2; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E281C;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #FAF7F2; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 520px; background-color: #FFFFFF; border-radius: 20px; border: 1px solid #E7DFD0; overflow: hidden; box-shadow: 0 4px 16px rgba(38, 58, 35, 0.06);">
          <!-- Header Banner -->
          <tr>
            <td style="background-color: #263A23; padding: 32px 30px; text-align: center;">
              <h1 style="margin: 0; color: #F3ECE0; font-family: Georgia, serif; font-size: 24px; font-weight: 700; letter-spacing: 0.5px;">
                MANEYINDHA MARUKATTE
              </h1>
              <p style="margin: 6px 0 0 0; color: #D2DEC9; font-size: 13px; font-weight: 500;">
                ಮನೆಯಿಂದ ಮಾರುಕಟ್ಟೆ · From Home to Marketplace
              </p>
            </td>
          </tr>

          <!-- Content Body -->
          <tr>
            <td style="padding: 36px 32px;">
              <h2 style="margin: 0 0 12px 0; color: #263A23; font-family: Georgia, serif; font-size: 20px;">
                Your Verification Code
              </h2>
              <p style="margin: 0 0 24px 0; color: #4E5E4C; font-size: 15px; line-height: 1.5;">
                Welcome to Maneyindha Marukatte. Use the single-use code below to complete your login or registration:
              </p>

              <!-- OTP Code Display -->
              <div style="background-color: #F3ECE0; border: 2px dashed #C35634; border-radius: 14px; padding: 22px; text-align: center; margin: 0 0 24px 0;">
                <span style="font-family: 'Courier New', Courier, monospace; font-size: 34px; font-weight: 700; letter-spacing: 8px; color: #C35634; display: inline-block;">
                  ${otp}
                </span>
              </div>

              <!-- Important Notices -->
              <table role="presentation" width="100%" style="background-color: #EFF5EC; border-radius: 10px; padding: 12px 16px; margin-bottom: 24px;">
                <tr>
                  <td style="color: #263A23; font-size: 13px; line-height: 1.5;">
                    ⏱ <strong>Valid for 5 minutes only.</strong><br>
                    🔒 Never share this code with anyone. Our team will never ask for your OTP.
                  </td>
                </tr>
              </table>

              <p style="margin: 0; color: #7A8A78; font-size: 13px; line-height: 1.5;">
                If you did not request this verification code, please disregard this email or contact support if you have concerns.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #FAF7F2; padding: 20px 32px; text-align: center; border-top: 1px solid #E7DFD0;">
              <p style="margin: 0; color: #7A8A78; font-size: 12px;">
                Empowering home-based women entrepreneurs across India.<br>
                © ${new Date().getFullYear()} Maneyindha Marukatte. All rights reserved.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
  `.trim();
}

/**
 * Sends a 6-digit OTP email to the given recipient via Resend.
 *
 * @param {Object} options
 * @param {string} options.to - Recipient email
 * @param {string} options.otp - Plain 6-digit OTP
 * @returns {Promise<{ delivered: boolean, id?: string }>}
 */
async function sendOtpEmail({ to, otp }) {
  if (!to || !otp) {
    throw new AppError('Recipient email and OTP are required for delivery', 400);
  }

  const apiKey = process.env.RESEND_API_KEY;
  const fromAddress = process.env.EMAIL_FROM || 'Maneyindha Marukatte <onboarding@resend.dev>';

  // Development / sandbox fallback when no API key has been configured yet
  if (!apiKey || apiKey === 're_your_api_key_here') {
    if (process.env.NODE_ENV === 'production') {
      logger.error('RESEND_API_KEY is not configured in production environment');
      throw new AppError('Email delivery service is currently not configured', 503);
    }
    logger.warn(`[EmailService] Simulated OTP delivery to ${to} (RESEND_API_KEY not configured)`);
    return { delivered: true, simulated: true };
  }

  const payload = {
    from: fromAddress,
    to: [to],
    subject: `${otp} is your Maneyindha Marukatte verification code`,
    html: buildOtpEmailHtml(otp),
    text: `Your Maneyindha Marukatte verification code is: ${otp}\n\nThis code is valid for 5 minutes. Never share this code with anyone.`,
  };

  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (!res.ok) {
      const errBody = await res.json().catch(() => ({}));
      logger.error('Resend API delivery failure:', { status: res.status, error: errBody });
      throw new AppError(errBody.message || 'Failed to dispatch verification email via Resend', 502);
    }

    const data = await res.json();
    logger.info(`OTP email successfully dispatched to ${to}`, { messageId: data.id });
    return { delivered: true, id: data.id };
  } catch (error) {
    if (error instanceof AppError) throw error;
    logger.error('Unexpected error in email dispatch:', error);
    throw new AppError('Unable to send verification email. Please check your network or try again.', 502);
  }
}

module.exports = {
  sendOtpEmail,
  buildOtpEmailHtml,
};
