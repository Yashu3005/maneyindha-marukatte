const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const Otp = require('../models/Otp');
const emailService = require('./email.service');
const AppError = require('../utils/AppError');

const OTP_EXPIRY_MS = 5 * 60 * 1000; // 5 minutes
const OTP_COOLDOWN_MS = 60 * 1000;   // 60 seconds cooldown between resends
const MAX_OTP_ATTEMPTS = 3;          // Max failed attempts before OTP invalidation

function hashOtp(otp) {
  return crypto.createHash('sha256').update(String(otp).trim()).digest('hex');
}

function isValidEmail(email) {
  return typeof email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

function issueTokens(user) {
  const payload = { id: user._id, role: user.role };
  return {
    accessToken: jwt.sign(payload, process.env.JWT_SECRET, {
      expiresIn: process.env.JWT_EXPIRES_IN || '15m',
    }),
    refreshToken: jwt.sign(payload, process.env.JWT_REFRESH_SECRET, {
      expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d',
    }),
  };
}

function sanitize(user) {
  const {
    _id,
    name,
    email,
    phone,
    role,
    avatarUrl,
    language,
    username,
    profileComplete,
    addresses,
    bankAccount,
  } = user;
  return {
    id: _id,
    _id,
    name,
    email,
    phone,
    role,
    avatarUrl,
    language,
    username,
    profileComplete,
    addresses,
    bankAccount,
  };
}

exports.issueTokens = issueTokens;
exports.sanitize = sanitize;
exports.hashOtp = hashOtp;

exports.register = async ({ name, email, phone, password, role }) => {
  const or = [];
  if (email) or.push({ email: email.toLowerCase().trim() });
  if (phone) or.push({ phone: phone.trim() });
  const existing = or.length ? await User.findOne({ $or: or }) : null;
  if (existing) throw new AppError('An account with this email or phone already exists', 409);

  // Prevent self-assignment of administrative roles
  const allowedRoles = ['customer', 'entrepreneur', 'delivery_partner'];
  const safeRole = allowedRoles.includes(role) ? role : 'customer';

  const passwordHash = await bcrypt.hash(password, 12);
  const user = await User.create({
    name: name.trim(),
    email: email ? email.toLowerCase().trim() : undefined,
    phone: phone ? phone.trim() : undefined,
    passwordHash,
    role: safeRole,
    profileComplete: true,
  });

  return { user: sanitize(user), ...issueTokens(user) };
};

exports.login = async ({ email, phone, username, password }) => {
  const query = email
    ? { email: email.toLowerCase().trim() }
    : phone
      ? { phone: phone.trim() }
      : { username: username?.toLowerCase().trim() };

  const user = await User.findOne(query).select('+passwordHash');
  if (!user || !(await bcrypt.compare(password, user.passwordHash || ''))) {
    throw new AppError('Invalid email or password', 401);
  }
  if (!user.isActive) throw new AppError('Account is disabled. Please contact support.', 403);

  return { user: sanitize(user), ...issueTokens(user) };
};

exports.refresh = async (refreshToken) => {
  if (!refreshToken) throw new AppError('Refresh token required', 400);
  try {
    const payload = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    const user = await User.findById(payload.id);
    if (!user || !user.isActive) throw new Error();
    return issueTokens(user);
  } catch {
    throw new AppError('Invalid or expired refresh token', 401);
  }
};

// --- Secure Email OTP Implementation ---

/**
 * Generates and delivers a cryptographically secure 6-digit OTP via Resend.
 * Enforces a 60-second cooldown between requests and sets a 5-minute expiry.
 */
exports.sendOtp = async (rawEmail, purpose = 'verification') => {
  if (!rawEmail || !isValidEmail(rawEmail)) {
    throw new AppError('A valid email address is required', 422);
  }
  const email = rawEmail.toLowerCase().trim();
  const validPurposes = ['registration', 'login', 'verification'];
  const safePurpose = validPurposes.includes(purpose) ? purpose : 'verification';

  // Rate-limiting / resend cooldown protection
  const existing = await Otp.findOne({ email, purpose: safePurpose });
  if (existing && existing.lastResendAt) {
    const elapsed = Date.now() - new Date(existing.lastResendAt).getTime();
    if (elapsed < OTP_COOLDOWN_MS) {
      const waitSeconds = Math.ceil((OTP_COOLDOWN_MS - elapsed) / 1000);
      throw new AppError(`Please wait ${waitSeconds}s before requesting a new verification code`, 429);
    }
  }

  // Generate a cryptographically secure 6-digit OTP
  const otp = String(crypto.randomInt(100000, 1000000));
  const hashedOtp = hashOtp(otp);

  // Deliver the OTP via Resend email service FIRST (never save or pretend if email fails!)
  await emailService.sendOtpEmail({ to: email, otp });

  // Invalidate any existing active or superseded OTPs for this email and purpose
  await Otp.deleteMany({ email, purpose: safePurpose });

  const now = new Date();
  const expiresAt = new Date(now.getTime() + OTP_EXPIRY_MS);

  // Store hashed OTP with 5-minute TTL index
  await Otp.create({
    email,
    hashedOtp,
    purpose: safePurpose,
    attempts: 0,
    lastResendAt: now,
    expiresAt,
  });

  // Never expose plaintext OTP in response or production logs
  return {
    sent: true,
    email,
    expiresIn: 300,
    resendCooldown: 60,
  };
};

/**
 * Verifies the 6-digit OTP using constant-time hash comparison.
 * Enforces maximum 3 attempts before permanently invalidating the OTP.
 */
exports.verifyOtp = async ({ email: rawEmail, otp, purpose = 'verification' }) => {
  if (!rawEmail || !otp) {
    throw new AppError('Email and OTP are both required', 422);
  }
  const email = rawEmail.toLowerCase().trim();
  const cleanOtp = String(otp).trim();
  const safePurpose = ['registration', 'login', 'verification'].includes(purpose) ? purpose : 'verification';

  const record = await Otp.findOne({ email, purpose: safePurpose });
  if (!record) {
    throw new AppError('Verification code expired or not requested. Please request a new code.', 401);
  }

  // Check if expired
  if (new Date() > record.expiresAt) {
    await Otp.deleteOne({ _id: record._id });
    throw new AppError('Verification code has expired. Please request a new code.', 401);
  }

  // Check attempt threshold (brute-force defense)
  if (record.attempts >= MAX_OTP_ATTEMPTS) {
    await Otp.deleteOne({ _id: record._id });
    throw new AppError('Too many failed attempts. For your security, this code has been cancelled.', 429);
  }

  // Constant-time hash verification
  const incomingHash = hashOtp(cleanOtp);
  const isMatch = crypto.timingSafeEqual(
    Buffer.from(incomingHash, 'hex'),
    Buffer.from(record.hashedOtp, 'hex')
  );

  if (!isMatch) {
    record.attempts += 1;
    await record.save();

    const remaining = MAX_OTP_ATTEMPTS - record.attempts;
    if (remaining <= 0) {
      await Otp.deleteOne({ _id: record._id });
      throw new AppError('Incorrect verification code. Maximum attempts reached. Please request a new code.', 429);
    }
    throw new AppError(`Incorrect verification code. ${remaining} attempt(s) remaining.`, 401);
  }

  // Invalidate OTP immediately upon successful verification (prevents replay)
  await Otp.deleteOne({ _id: record._id });

  // Fetch or create user
  let user = await User.findOne({ email });
  let isNewUser = false;

  if (!user) {
    isNewUser = true;
    user = await User.create({
      name: 'New Member',
      email,
      role: 'customer', // Always default to customer; cannot self-assign admin
      isEmailVerified: true,
      profileComplete: false,
    });
  } else {
    user.isEmailVerified = true;
    await user.save();
  }

  if (!user.isActive) {
    throw new AppError('Account is disabled. Please contact support.', 403);
  }

  return {
    user: sanitize(user),
    ...issueTokens(user),
    isNewUser,
  };
};

// --- Firebase exchange (legacy fallback) ---
const { getFirebase } = require('../config/firebase');

exports.exchangeFirebaseToken = async ({ idToken, role, name }) => {
  if (!idToken) throw new AppError('idToken required', 422);
  let decoded;
  try {
    decoded = await getFirebase().auth().verifyIdToken(idToken);
  } catch {
    throw new AppError('Invalid Firebase token', 401);
  }
  let user = await User.findOne({ firebaseUid: decoded.uid });
  if (!user) {
    const safeRole = ['customer', 'entrepreneur', 'delivery_partner'].includes(role) ? role : 'customer';
    user = await User.create({
      firebaseUid: decoded.uid,
      name: name || decoded.name || 'User',
      email: decoded.email,
      phone: decoded.phone_number?.replace('+91', ''),
      role: safeRole,
    });
  }
  if (!user.isActive) throw new AppError('Account disabled', 403);
  return { user: sanitize(user), ...issueTokens(user) };
};
