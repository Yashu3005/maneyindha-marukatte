const logger = require('../utils/logger');
const AppError = require('../utils/AppError');

const RESEND_API_URL = 'https://api.resend.com/emails';

/**
 * Builds the branded, responsive HTML email for OTP verification.
 * Subject: Verify Your Email – Maneyindha Marukatte
 */
function buildOtpEmailHtml(otp) {
  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Verify Your Email – Maneyindha Marukatte</title>
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
                ಮನೆಯಿಂದ ಮಾರುಕಟ್ಟೆ · Empowering Home-Based Women Entrepreneurs
              </p>
            </td>
          </tr>

          <!-- Content Body -->
          <tr>
            <td style="padding: 36px 32px;">
              <h2 style="margin: 0 0 12px 0; color: #263A23; font-family: Georgia, serif; font-size: 20px;">
                Verify Your Email Address
              </h2>
              <p style="margin: 0 0 24px 0; color: #4E5E4C; font-size: 15px; line-height: 1.5;">
                Welcome to Maneyindha Marukatte. Please use the six-digit verification code below to verify your email address:
              </p>

              <!-- OTP Code Display -->
              <div style="background-color: #F3ECE0; border: 2px dashed #C35634; border-radius: 14px; padding: 22px; text-align: center; margin: 0 0 24px 0;">
                <span style="font-family: 'Courier New', Courier, monospace; font-size: 34px; font-weight: 700; letter-spacing: 8px; color: #C35634; display: inline-block;">
                  ${otp}
                </span>
              </div>

              <!-- Expiry & Security Notice -->
              <table role="presentation" width="100%" style="background-color: #EFF5EC; border-radius: 10px; padding: 14px 16px; margin-bottom: 24px;">
                <tr>
                  <td style="color: #263A23; font-size: 13px; line-height: 1.5;">
                    ⏱ <strong>This code is valid for 5 minutes only.</strong><br>
                    🔒 <strong>Security Notice:</strong> Do not share this OTP with anyone. Our support team will never ask for your verification code.
                  </td>
                </tr>
              </table>

              <p style="margin: 0; color: #7A8A78; font-size: 13px; line-height: 1.5;">
                If you did not request this verification code, please ignore this email. No changes will be made to your account.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #FAF7F2; padding: 20px 32px; text-align: center; border-top: 1px solid #E7DFD0;">
              <p style="margin: 0; color: #7A8A78; font-size: 12px; line-height: 1.4;">
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
 * Dispatches a real verification OTP email to the exact recipient address via Resend.
 *
 * Never simulates delivery: if credentials are missing or Resend rejects the request,
 * throws an explicit AppError.
 *
 * @param {Object} options
 * @param {string} options.to - Exact recipient email address
 * @param {string} options.otp - 6-digit OTP string
 * @returns {Promise<{ delivered: boolean, id: string }>}
 */
async function sendOtpEmail({ to, otp }) {
  if (!to || !otp) {
    throw new AppError('Recipient email address and OTP are required for delivery', 400);
  }

  const apiKey = process.env.RESEND_API_KEY;
  const fromAddress = process.env.EMAIL_FROM || 'Maneyindha Marukatte <onboarding@resend.dev>';

  // Explicit failure if the real API key is missing — NEVER simulate delivery
  if (!apiKey || apiKey.startsWith('re_placeholder') || apiKey === 'your_api_key') {
    logger.error('RESEND_API_KEY is not configured in backend environment');
    throw new AppError(
      'Email delivery service is not configured. Please set a valid RESEND_API_KEY in your backend .env file.',
      503
    );
  }

  const payload = {
    from: fromAddress,
    to: [to],
    subject: 'Verify Your Email – Maneyindha Marukatte',
    html: buildOtpEmailHtml(otp),
    text: `Welcome to Maneyindha Marukatte.\n\nYour 6-digit verification code is: ${otp}\n\nThis code is valid for 5 minutes only.\nDo not share this code with anyone. If you did not request this code, you can safely ignore this email.`,
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

    const data = await res.json().catch(() => ({}));

    if (!res.ok) {
      logger.error('Resend API rejected email dispatch:', { status: res.status, error: data });
      const errorMessage = data.message || `Resend email delivery failed (status ${res.status})`;
      throw new AppError(`Email delivery failed: ${errorMessage}`, 502);
    }

    logger.info(`Real OTP email successfully dispatched via Resend to ${to}`, { messageId: data.id });
    return { delivered: true, id: data.id };
  } catch (error) {
    if (error instanceof AppError) throw error;
    logger.error('Network or transport failure during email delivery:', error);
    throw new AppError(
      'Unable to deliver verification email. Please verify your internet connection or email service configuration.',
      502
    );
  }
}

/**
 * Builds branded HTML for customer order confirmation.
 */
function buildOrderPlacedHtml({ orderNumber, customerName, items = [], amounts = {}, deliveryAddress }) {
  const addressText = deliveryAddress
    ? [deliveryAddress.line1, deliveryAddress.line2, deliveryAddress.city, deliveryAddress.pincode].filter(Boolean).join(', ')
    : 'Self Pickup';

  const itemsHtml = items.map((i) => `
    <tr>
      <td style="padding: 10px 0; border-bottom: 1px solid #ECE4D6; color: #1E281C; font-size: 14px;">
        <strong>${i.name}</strong> × ${i.quantity}
      </td>
      <td align="right" style="padding: 10px 0; border-bottom: 1px solid #ECE4D6; color: #1E281C; font-size: 14px; font-weight: 600;">
        ₹${((i.unitPrice || 0) * (i.quantity || 1)).toFixed(2)}
      </td>
    </tr>
  `).join('');

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Order Confirmed – Maneyindha Marukatte</title>
</head>
<body style="margin: 0; padding: 0; background-color: #FAF7F2; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E281C;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #FAF7F2; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 540px; background-color: #FFFFFF; border-radius: 20px; border: 1px solid #E7DFD0; overflow: hidden; box-shadow: 0 4px 16px rgba(38, 58, 35, 0.06);">
          <tr>
            <td style="background-color: #263A23; padding: 28px 30px; text-align: center;">
              <h1 style="margin: 0; color: #F3ECE0; font-family: Georgia, serif; font-size: 22px;">MANEYINDHA MARUKATTE</h1>
              <p style="margin: 4px 0 0 0; color: #D2DEC9; font-size: 13px;">ಮನೆಯಿಂದ ಮಾರುಕಟ್ಟೆ · Order Confirmation</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 32px 30px;">
              <h2 style="margin: 0 0 8px 0; color: #263A23; font-size: 18px;">Namaskara ${customerName || 'Customer'}! 🙏</h2>
              <p style="margin: 0 0 20px 0; color: #4E5E4C; font-size: 14px; line-height: 1.5;">
                Your order <strong>#${orderNumber}</strong> has been successfully placed with our home entrepreneur!
              </p>
              
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-bottom: 20px;">
                <thead>
                  <tr style="border-bottom: 2px solid #263A23;">
                    <th align="left" style="padding-bottom: 8px; color: #263A23; font-size: 13px;">Item</th>
                    <th align="right" style="padding-bottom: 8px; color: #263A23; font-size: 13px;">Amount</th>
                  </tr>
                </thead>
                <tbody>
                  ${itemsHtml}
                </tbody>
              </table>

              <div style="background-color: #F8F5EE; border-radius: 12px; padding: 16px; margin-bottom: 20px;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td style="padding-bottom: 6px; font-size: 13px; color: #4E5E4C;">Subtotal:</td>
                    <td align="right" style="padding-bottom: 6px; font-size: 13px; color: #4E5E4C;">₹${(amounts.subtotal || 0).toFixed(2)}</td>
                  </tr>
                  ${amounts.discount ? `
                  <tr>
                    <td style="padding-bottom: 6px; font-size: 13px; color: #C35634;">Discount:</td>
                    <td align="right" style="padding-bottom: 6px; font-size: 13px; color: #C35634;">-₹${(amounts.discount || 0).toFixed(2)}</td>
                  </tr>` : ''}
                  <tr>
                    <td style="padding-bottom: 6px; font-size: 13px; color: #4E5E4C;">Delivery Fee:</td>
                    <td align="right" style="padding-bottom: 6px; font-size: 13px; color: #4E5E4C;">₹${(amounts.deliveryFee || 0).toFixed(2)}</td>
                  </tr>
                  <tr>
                    <td colspan="2" style="border-top: 1px dashed #D2DEC9; padding-top: 8px;"></td>
                  </tr>
                  <tr>
                    <td style="font-size: 15px; font-weight: 700; color: #263A23;">Total:</td>
                    <td align="right" style="font-size: 15px; font-weight: 700; color: #263A23;">₹${(amounts.total || 0).toFixed(2)}</td>
                  </tr>
                </table>
              </div>

              <p style="margin: 0; font-size: 13px; color: #7A8A78;">
                📍 <strong>Delivery Address:</strong> ${addressText}
              </p>
            </td>
          </tr>
          <tr>
            <td style="background-color: #FAF7F2; padding: 18px 30px; text-align: center; border-top: 1px solid #E7DFD0;">
              <p style="margin: 0; color: #7A8A78; font-size: 12px;">Thank you for supporting women entrepreneurs in your neighborhood!</p>
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
 * Builds branded HTML for customer order status changes.
 */
function buildOrderStatusHtml({ orderNumber, customerName, newStatus, trackingNotes }) {
  const statusLabels = {
    confirmed: 'Confirmed and being prepared',
    preparing: 'Being freshly prepared by entrepreneur',
    ready_for_pickup: 'Packed and ready for pickup',
    picked_up: 'Picked up by delivery partner',
    out_for_delivery: 'Out for delivery to your address',
    delivered: 'Delivered successfully! Enjoy your items',
    cancelled: 'Cancelled',
  };

  const statusTitle = statusLabels[newStatus] || newStatus.replace(/_/g, ' ');

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Order Status Update – Maneyindha Marukatte</title>
</head>
<body style="margin: 0; padding: 0; background-color: #FAF7F2; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E281C;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #FAF7F2; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 520px; background-color: #FFFFFF; border-radius: 20px; border: 1px solid #E7DFD0; overflow: hidden; box-shadow: 0 4px 16px rgba(38, 58, 35, 0.06);">
          <tr>
            <td style="background-color: #263A23; padding: 26px 30px; text-align: center;">
              <h1 style="margin: 0; color: #F3ECE0; font-family: Georgia, serif; font-size: 20px;">MANEYINDHA MARUKATTE</h1>
              <p style="margin: 4px 0 0 0; color: #D2DEC9; font-size: 13px;">Order Status Update</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 30px 28px;">
              <h2 style="margin: 0 0 10px 0; color: #263A23; font-size: 18px;">Namaskara ${customerName || 'Customer'},</h2>
              <p style="margin: 0 0 20px 0; color: #4E5E4C; font-size: 14px; line-height: 1.5;">
                Your order <strong>#${orderNumber}</strong> status has been updated:
              </p>
              
              <div style="background-color: #EFF5EC; border-left: 4px solid #263A23; border-radius: 8px; padding: 16px; margin-bottom: 20px;">
                <p style="margin: 0; font-size: 16px; font-weight: 700; color: #263A23;">
                  ${statusTitle}
                </p>
                ${trackingNotes ? `<p style="margin: 6px 0 0 0; font-size: 13px; color: #4E5E4C;">Note: ${trackingNotes}</p>` : ''}
              </div>

              <p style="margin: 0; color: #7A8A78; font-size: 13px;">
                You can track live updates anytime from your Orders page in the app.
              </p>
            </td>
          </tr>
          <tr>
            <td style="background-color: #FAF7F2; padding: 16px 28px; text-align: center; border-top: 1px solid #E7DFD0;">
              <p style="margin: 0; color: #7A8A78; font-size: 12px;">© ${new Date().getFullYear()} Maneyindha Marukatte</p>
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
 * Builds branded HTML for seller when an incoming order is placed.
 */
function buildSellerAlertHtml({ sellerName, orderNumber, items = [], amounts = {} }) {
  const itemsList = items.map((i) => `<li><strong>${i.name}</strong> × ${i.quantity}</li>`).join('');

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>New Order Alert – Maneyindha Marukatte</title>
</head>
<body style="margin: 0; padding: 0; background-color: #FAF7F2; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #1E281C;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color: #FAF7F2; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 520px; background-color: #FFFFFF; border-radius: 20px; border: 1px solid #E7DFD0; overflow: hidden; box-shadow: 0 4px 16px rgba(38, 58, 35, 0.06);">
          <tr>
            <td style="background-color: #C35634; padding: 26px 30px; text-align: center;">
              <h1 style="margin: 0; color: #FFFFFF; font-family: Georgia, serif; font-size: 20px;">MANEYINDHA MARUKATTE</h1>
              <p style="margin: 4px 0 0 0; color: #FEE8DF; font-size: 13px;">New Order Received! 🛍️</p>
            </td>
          </tr>
          <tr>
            <td style="padding: 30px 28px;">
              <h2 style="margin: 0 0 10px 0; color: #263A23; font-size: 18px;">Namaskara ${sellerName || 'Entrepreneur'},</h2>
              <p style="margin: 0 0 18px 0; color: #4E5E4C; font-size: 14px; line-height: 1.5;">
                You have received a new customer order <strong>#${orderNumber}</strong>!
              </p>
              
              <div style="background-color: #F8F5EE; border-radius: 12px; padding: 16px; margin-bottom: 20px;">
                <p style="margin: 0 0 8px 0; font-size: 14px; font-weight: 700; color: #263A23;">Order Summary:</p>
                <ul style="margin: 0 0 12px 18px; padding: 0; color: #4E5E4C; font-size: 13px;">
                  ${itemsList}
                </ul>
                <p style="margin: 0; font-size: 15px; font-weight: 700; color: #C35634;">
                  Total Amount: ₹${(amounts.total || 0).toFixed(2)}
                </p>
              </div>

              <p style="margin: 0; color: #7A8A78; font-size: 13px;">
                Please open your Seller Dashboard to accept and prepare this order.
              </p>
            </td>
          </tr>
          <tr>
            <td style="background-color: #FAF7F2; padding: 16px 28px; text-align: center; border-top: 1px solid #E7DFD0;">
              <p style="margin: 0; color: #7A8A78; font-size: 12px;">Empowering women home entrepreneurs · Maneyindha Marukatte</p>
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
 * Dispatches order confirmation email to customer via Resend.
 */
async function sendOrderConfirmationEmail({ to, customerName, orderNumber, items, amounts, deliveryAddress }) {
  if (!to) return { delivered: false, reason: 'missing_recipient' };
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey || apiKey.startsWith('re_placeholder') || apiKey === 'your_api_key') {
    logger.info(`Order confirmation email skipped for #${orderNumber}: RESEND_API_KEY unconfigured`);
    return { delivered: false, reason: 'unconfigured' };
  }

  const fromAddress = process.env.EMAIL_FROM || 'Maneyindha Marukatte <onboarding@resend.dev>';
  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [to],
        subject: `Order Confirmed #${orderNumber} – Maneyindha Marukatte`,
        html: buildOrderPlacedHtml({ orderNumber, customerName, items, amounts, deliveryAddress }),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      logger.info(`Order confirmation email sent to ${to} for #${orderNumber}`, { id: data.id });
      return { delivered: true, id: data.id };
    }
    logger.warn(`Resend rejected order confirmation email for #${orderNumber}:`, data);
    return { delivered: false, error: data };
  } catch (err) {
    logger.warn(`Network error sending order confirmation email for #${orderNumber}:`, err.message);
    return { delivered: false, error: err.message };
  }
}

/**
 * Dispatches order status update email to customer via Resend.
 */
async function sendOrderStatusEmail({ to, customerName, orderNumber, newStatus, trackingNotes }) {
  if (!to) return { delivered: false, reason: 'missing_recipient' };
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey || apiKey.startsWith('re_placeholder') || apiKey === 'your_api_key') {
    logger.info(`Order status email skipped for #${orderNumber}: RESEND_API_KEY unconfigured`);
    return { delivered: false, reason: 'unconfigured' };
  }

  const fromAddress = process.env.EMAIL_FROM || 'Maneyindha Marukatte <onboarding@resend.dev>';
  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [to],
        subject: `Order #${orderNumber} Status: ${newStatus.replace(/_/g, ' ')} – Maneyindha Marukatte`,
        html: buildOrderStatusHtml({ orderNumber, customerName, newStatus, trackingNotes }),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      logger.info(`Order status email sent to ${to} for #${orderNumber} (${newStatus})`, { id: data.id });
      return { delivered: true, id: data.id };
    }
    logger.warn(`Resend rejected order status email for #${orderNumber}:`, data);
    return { delivered: false, error: data };
  } catch (err) {
    logger.warn(`Network error sending order status email for #${orderNumber}:`, err.message);
    return { delivered: false, error: err.message };
  }
}

/**
 * Dispatches new order alert email to seller via Resend.
 */
async function sendSellerNewOrderEmail({ to, sellerName, orderNumber, items, amounts }) {
  if (!to) return { delivered: false, reason: 'missing_recipient' };
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey || apiKey.startsWith('re_placeholder') || apiKey === 'your_api_key') {
    logger.info(`Seller order alert skipped for #${orderNumber}: RESEND_API_KEY unconfigured`);
    return { delivered: false, reason: 'unconfigured' };
  }

  const fromAddress = process.env.EMAIL_FROM || 'Maneyindha Marukatte <onboarding@resend.dev>';
  try {
    const res = await fetch(RESEND_API_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [to],
        subject: `New Order Received #${orderNumber} – Maneyindha Marukatte`,
        html: buildSellerAlertHtml({ sellerName, orderNumber, items, amounts }),
      }),
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      logger.info(`Seller order alert sent to ${to} for #${orderNumber}`, { id: data.id });
      return { delivered: true, id: data.id };
    }
    logger.warn(`Resend rejected seller order alert for #${orderNumber}:`, data);
    return { delivered: false, error: data };
  } catch (err) {
    logger.warn(`Network error sending seller order alert for #${orderNumber}:`, err.message);
    return { delivered: false, error: err.message };
  }
}

module.exports = {
  sendOtpEmail,
  buildOtpEmailHtml,
  sendOrderConfirmationEmail,
  buildOrderPlacedHtml,
  sendOrderStatusEmail,
  buildOrderStatusHtml,
  sendSellerNewOrderEmail,
  buildSellerAlertHtml,
};
