// The sign-in email carries the same logo file the website uses.
const email = require('../src/services/email.service');
const fs = require('fs');
const path = require('path');

describe('logoUrl', () => {
  test('APP_URL wins; a trailing slash is tidied', () => {
    expect(email.logoUrl({ APP_URL: 'https://maneyindha-marukatte.vercel.app/' })).toBe('https://maneyindha-marukatte.vercel.app/brand/logo-email.png');
  });
  test('falls back to the first public https origin in CORS_ORIGINS, skipping localhost', () => {
    expect(email.logoUrl({ CORS_ORIGINS: 'http://localhost:3000, http://127.0.0.1:3000, https://shop.example.app, https://other.app' })).toBe('https://shop.example.app/brand/logo-email.png');
  });
  test('EMAIL_LOGO_URL overrides everything', () => {
    expect(email.logoUrl({ EMAIL_LOGO_URL: 'https://cdn.example.com/m.png', APP_URL: 'https://a.app' })).toBe('https://cdn.example.com/m.png');
  });
  test.each([
    ['nothing configured', {}],
    ['only localhost', { CORS_ORIGINS: 'http://localhost:3000' }],
    ['http (not https)', { EMAIL_LOGO_URL: 'http://cdn.example.com/m.png' }],
    ['attribute-breaking quote', { EMAIL_LOGO_URL: 'https://x.app/a.png" onerror="alert(1)' }],
    ['angle brackets', { APP_URL: 'https://x.app/<script>' }],
    ['whitespace', { APP_URL: 'https://x.app/a b' }],
  ])('no logo for %s', (_n, env) => {
    expect(email.logoUrl(env)).toBeNull();
  });
});

describe('sign-in email HTML', () => {
  const save = { ...process.env };
  afterEach(() => { process.env = { ...save }; });

  test('shows the logo image with alt text when a public URL is configured', () => {
    process.env.APP_URL = 'https://maneyindha-marukatte.vercel.app';
    const html = email._otpHtml('123456', 5);
    expect(html).toContain('<img src="https://maneyindha-marukatte.vercel.app/brand/logo-email.png"');
    expect(html).toContain('alt="Maneyindha Marukatte"');
    expect(html).toContain('123456');
  });
  test('without a public URL the email still works (text header, no broken image)', () => {
    delete process.env.APP_URL; delete process.env.EMAIL_LOGO_URL; delete process.env.CORS_ORIGINS;
    const html = email._otpHtml('123456', 5);
    expect(html).not.toContain('<img');
    expect(html).toContain('Maneyindha Marukatte');
    expect(html).toContain('123456');
  });
});

describe('one logo everywhere', () => {
  const web = path.resolve(__dirname, '../../frontend/web');
  const assets = path.resolve(__dirname, '../../frontend/assets/brand');
  const png = (f) => fs.readFileSync(f);
  test('the file referenced by the email exists, is a PNG, and the app uses the same artwork', () => {
    const emailLogo = png(path.join(web, 'brand/logo-email.png'));
    expect(emailLogo.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe(true);
    // email size (240 px) is a smaller copy of the in-app file (512 px): identical artwork, different size
    expect(emailLogo.readUInt32BE(16)).toBe(240);
    expect(png(path.join(web, 'brand/logo.png')).equals(png(path.join(assets, 'logo.png')))).toBe(true);
    expect(png(path.join(web, 'brand/logo.png')).readUInt32BE(16)).toBe(512);
    expect(emailLogo.length).toBeLessThan(100 * 1024); // light enough for email clients
  });
});
