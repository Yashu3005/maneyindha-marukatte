process.env.JWT_SECRET = 'test-jwt-secret-1234567890';
process.env.JWT_REFRESH_SECRET = 'test-jwt-refresh-secret-1234567890';
process.env.NODE_ENV = 'test';

const authService = require('../src/services/auth.service');
const emailService = require('../src/services/email.service');
const Otp = require('../src/models/Otp');
const User = require('../src/models/User');

describe('Email OTP Authentication Service', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  describe('OTP Generation and Dispatch (sendOtp)', () => {
    test('rejects missing or invalid email format with 422', async () => {
      await expect(authService.sendOtp('')).rejects.toThrow('valid email');
      await expect(authService.sendOtp('not-an-email')).rejects.toThrow('valid email');
    });

    test('generates secure 6-digit OTP, stores SHA-256 hash, and delivers email without exposing OTP in response', async () => {
      let createdDoc = null;
      jest.spyOn(Otp, 'findOne').mockResolvedValue(null);
      jest.spyOn(Otp, 'deleteMany').mockResolvedValue({ deletedCount: 0 });
      jest.spyOn(Otp, 'create').mockImplementation(async (data) => {
        createdDoc = data;
        return { _id: 'otp-id-123', ...data };
      });
      const emailSpy = jest.spyOn(emailService, 'sendOtpEmail').mockResolvedValue({ delivered: true });

      const email = 'entrepreneur@example.com';
      const result = await authService.sendOtp(email);

      // Verify response does NOT expose plaintext OTP or demoOtp
      expect(result.sent).toBe(true);
      expect(result.expiresIn).toBe(300); // 5 minutes
      expect(result.resendCooldown).toBe(60);
      expect(result.otp).toBeUndefined();
      expect(result.demoOtp).toBeUndefined();

      // Verify that database stored the hash, NOT plaintext
      expect(createdDoc).toBeDefined();
      expect(createdDoc.email).toBe(email);
      expect(createdDoc.hashedOtp).toHaveLength(64); // SHA-256 hex string length
      expect(createdDoc.attempts).toBe(0);

      // Verify email service received the plain OTP for dispatch
      expect(emailSpy).toHaveBeenCalledTimes(1);
      const emailArgs = emailSpy.mock.calls[0][0];
      expect(emailArgs.to).toBe(email);
      expect(emailArgs.otp).toMatch(/^\d{6}$/);

      // Confirm SHA-256 hash matches the dispatched OTP
      expect(authService.hashOtp(emailArgs.otp)).toBe(createdDoc.hashedOtp);
    });

    test('enforces 60-second resend cooldown and rejects premature requests with 429', async () => {
      // Existing active OTP requested 25 seconds ago
      const recentDate = new Date(Date.now() - 25 * 1000);
      jest.spyOn(Otp, 'findOne').mockResolvedValue({
        email: 'test@example.com',
        lastResendAt: recentDate,
      });

      await expect(authService.sendOtp('test@example.com')).rejects.toThrow(/Please wait \d+s before requesting a new verification code/);
    });

    test('supersedes and invalidates any previous active OTPs upon new request', async () => {
      // Existing OTP was requested 70 seconds ago (cooldown expired)
      const oldDate = new Date(Date.now() - 70 * 1000);
      jest.spyOn(Otp, 'findOne').mockResolvedValue({
        email: 'test@example.com',
        lastResendAt: oldDate,
      });
      const deleteManySpy = jest.spyOn(Otp, 'deleteMany').mockResolvedValue({ deletedCount: 1 });
      jest.spyOn(Otp, 'create').mockResolvedValue({ _id: 'new-otp-id' });
      jest.spyOn(emailService, 'sendOtpEmail').mockResolvedValue({ delivered: true });

      await authService.sendOtp('test@example.com');
      expect(deleteManySpy).toHaveBeenCalledWith({ email: 'test@example.com', purpose: 'verification' });
    });

    test('never saves OTP or pretends success if email provider fails to send', async () => {
      jest.spyOn(Otp, 'findOne').mockResolvedValue(null);
      const createSpy = jest.spyOn(Otp, 'create').mockResolvedValue({});
      jest.spyOn(emailService, 'sendOtpEmail').mockRejectedValue(new Error('Resend rate limit exceeded'));

      await expect(authService.sendOtp('user@example.com')).rejects.toThrow('Resend rate limit exceeded');
      expect(createSpy).not.toHaveBeenCalled();
    });
  });

  describe('OTP Verification (verifyOtp)', () => {
    test('fails if OTP or email is missing with 422', async () => {
      await expect(authService.verifyOtp({ email: '', otp: '123456' })).rejects.toThrow('required');
      await expect(authService.verifyOtp({ email: 'test@example.com', otp: '' })).rejects.toThrow('required');
    });

    test('fails with 401 when code was not requested or record not found', async () => {
      jest.spyOn(Otp, 'findOne').mockResolvedValue(null);
      await expect(authService.verifyOtp({ email: 'test@example.com', otp: '123456' }))
        .rejects.toThrow('Verification code expired or not requested');
    });

    test('fails with 401 and deletes record when OTP is expired (5 minutes passed)', async () => {
      const expiredDate = new Date(Date.now() - 6 * 60 * 1000);
      const record = {
        _id: 'otp-id-expired',
        email: 'test@example.com',
        hashedOtp: authService.hashOtp('123456'),
        expiresAt: expiredDate,
        attempts: 0,
      };
      jest.spyOn(Otp, 'findOne').mockResolvedValue(record);
      const deleteSpy = jest.spyOn(Otp, 'deleteOne').mockResolvedValue({});

      await expect(authService.verifyOtp({ email: 'test@example.com', otp: '123456' }))
        .rejects.toThrow('Verification code has expired');
      expect(deleteSpy).toHaveBeenCalledWith({ _id: 'otp-id-expired' });
    });

    test('increments attempt count on incorrect OTP and reports remaining attempts', async () => {
      const futureDate = new Date(Date.now() + 4 * 60 * 1000);
      const saveSpy = jest.fn();
      const record = {
        _id: 'otp-id-wrong',
        email: 'test@example.com',
        hashedOtp: authService.hashOtp('123456'),
        expiresAt: futureDate,
        attempts: 0,
        save: saveSpy,
      };
      jest.spyOn(Otp, 'findOne').mockResolvedValue(record);

      await expect(authService.verifyOtp({ email: 'test@example.com', otp: '999999' }))
        .rejects.toThrow('Incorrect verification code. 2 attempt(s) remaining.');
      expect(record.attempts).toBe(1);
      expect(saveSpy).toHaveBeenCalledTimes(1);
    });

    test('invalidates OTP and locks out after reaching 3 failed attempts (brute-force defense)', async () => {
      const futureDate = new Date(Date.now() + 4 * 60 * 1000);
      const saveSpy = jest.fn();
      const record = {
        _id: 'otp-id-locked',
        email: 'test@example.com',
        hashedOtp: authService.hashOtp('123456'),
        expiresAt: futureDate,
        attempts: 2, // 2 previous attempts; this third failed attempt will exhaust limit
        save: saveSpy,
      };
      jest.spyOn(Otp, 'findOne').mockResolvedValue(record);
      const deleteSpy = jest.spyOn(Otp, 'deleteOne').mockResolvedValue({});

      await expect(authService.verifyOtp({ email: 'test@example.com', otp: '000000' }))
        .rejects.toThrow('Maximum attempts reached');
      expect(deleteSpy).toHaveBeenCalledWith({ _id: 'otp-id-locked' });
    });

    test('successful verification invalidates OTP, issues JWT tokens, and creates customer without admin privileges', async () => {
      const futureDate = new Date(Date.now() + 4 * 60 * 1000);
      const plainOtp = '482910';
      const record = {
        _id: 'otp-id-valid',
        email: 'freshuser@example.com',
        hashedOtp: authService.hashOtp(plainOtp),
        expiresAt: futureDate,
        attempts: 0,
      };
      jest.spyOn(Otp, 'findOne').mockResolvedValue(record);
      const deleteSpy = jest.spyOn(Otp, 'deleteOne').mockResolvedValue({});

      // Mock user not existing initially -> creates new user
      jest.spyOn(User, 'findOne').mockResolvedValue(null);
      let createdUser = null;
      jest.spyOn(User, 'create').mockImplementation(async (userData) => {
        createdUser = {
          _id: 'new-user-id-555',
          isActive: true,
          ...userData,
        };
        return createdUser;
      });

      const response = await authService.verifyOtp({
        email: 'freshuser@example.com',
        otp: plainOtp,
      });

      // Verification must immediately delete OTP to prevent replay
      expect(deleteSpy).toHaveBeenCalledWith({ _id: 'otp-id-valid' });

      // Validates response tokens and user info
      expect(response.accessToken).toBeDefined();
      expect(response.refreshToken).toBeDefined();
      expect(response.isNewUser).toBe(true);
      expect(response.user.email).toBe('freshuser@example.com');
      expect(response.user.role).toBe('customer'); // Must be customer, never admin
    });
  });

  describe('Role Escalation Protection', () => {
    test('register prevents user from assigning themselves admin role', async () => {
      jest.spyOn(User, 'findOne').mockResolvedValue(null);
      let savedUser = null;
      jest.spyOn(User, 'create').mockImplementation(async (data) => {
        savedUser = { _id: 'u-1', isActive: true, ...data };
        return savedUser;
      });

      await authService.register({
        name: 'Attacker',
        email: 'attacker@example.com',
        password: 'password12345',
        role: 'admin', // Malicious attempt to claim admin
      });

      // Role must be forced to customer
      expect(savedUser.role).toBe('customer');
    });
  });

  describe('Email Template Generation & Real Dispatch Verification', () => {
    test('renders branded HTML with correct OTP and security warnings', () => {
      const html = emailService.buildOtpEmailHtml('749201');
      expect(html).toContain('749201');
      expect(html).toContain('This code is valid for 5 minutes only');
      expect(html).toContain('MANEYINDHA MARUKATTE');
      expect(html).toContain('Do not share this OTP with anyone');
    });

    test('sendOtpEmail throws explicit 503 error when RESEND_API_KEY is not configured (never simulates delivery)', async () => {
      const prevKey = process.env.RESEND_API_KEY;
      delete process.env.RESEND_API_KEY;

      await expect(
        emailService.sendOtpEmail({ to: 'realuser@gmail.com', otp: '123456' })
      ).rejects.toThrow('Email delivery service is not configured');

      process.env.RESEND_API_KEY = prevKey;
    });

    test('sendOtpEmail dispatches real HTTP POST to Resend API endpoint with exact recipient', async () => {
      process.env.RESEND_API_KEY = 're_test_real_key_123456';
      const fetchSpy = jest.spyOn(global, 'fetch').mockResolvedValue({
        ok: true,
        json: async () => ({ id: 'email_msg_123' }),
      });

      const res = await emailService.sendOtpEmail({ to: 'specific.recipient@domain.com', otp: '852963' });

      expect(res.delivered).toBe(true);
      expect(res.id).toBe('email_msg_123');
      expect(fetchSpy).toHaveBeenCalledTimes(1);

      const [url, options] = fetchSpy.mock.calls[0];
      expect(url).toBe('https://api.resend.com/emails');
      expect(options.headers['Authorization']).toBe('Bearer re_test_real_key_123456');

      const sentBody = JSON.parse(options.body);
      expect(sentBody.to).toEqual(['specific.recipient@domain.com']);
      expect(sentBody.subject).toBe('Verify Your Email – Maneyindha Marukatte');
      expect(sentBody.text).toContain('852963');
    });
  });
});
