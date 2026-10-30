// Suspend / restore: reasons, idempotence, shop cascade, and the notices people get (no database, no network).
const Business = require('../src/models/Business');
const User = require('../src/models/User');
const RefreshSession = require('../src/models/RefreshSession');
const Notification = require('../src/models/Notification');
const admin = require('../src/services/admin.service');
const email = require('../src/services/email.service');
const notifications = require('../src/services/notification.service');
const { oid } = require('./helpers');

let user; let shop; let owner; let mails;
beforeEach(() => {
  jest.restoreAllMocks();
  mails = [];
  user = { _id: oid(), role: 'entrepreneur', email: 'asha@example.com', isActive: true, deletedAt: null, save: jest.fn().mockResolvedValue() };
  shop = { _id: oid(), owner: user._id, name: 'Asha Bakes', isActive: true, save: jest.fn().mockResolvedValue() };
  owner = { email: 'asha@example.com', isActive: true };
  jest.spyOn(User, 'findById').mockImplementation((id) => {
    const r = String(id) === String(user._id) ? user : null;
    const q = Promise.resolve(r); q.select = async () => (r && r === user ? owner : r); return q;
  });
  jest.spyOn(Business, 'findOne').mockResolvedValue(shop);
  jest.spyOn(Business, 'updateMany').mockResolvedValue({});
  jest.spyOn(RefreshSession, 'deleteMany').mockResolvedValue({});
  jest.spyOn(Notification, 'create').mockResolvedValue({});
  jest.spyOn(email, 'sendNoticeEmail').mockImplementation(async (m) => { mails.push(m); return { sent: true }; });
});

describe('member suspend / restore', () => {
  test('a reason is required to suspend, and nothing changes without one', async () => {
    await expect(admin.setUserActive(user._id, false, {})).rejects.toMatchObject({ statusCode: 422 });
    await expect(admin.setUserActive(user._id, false, { reason: ' a ' })).rejects.toMatchObject({ statusCode: 422 });
    expect(user.isActive).toBe(true); expect(user.save).not.toHaveBeenCalled(); expect(mails).toHaveLength(0);
  });
  test('suspending signs them out, hides their shops, and tells them in the app and by email (with the reason)', async () => {
    const r = await admin.setUserActive(user._id, false, { reason: 'Reported for selling unsafe food' });
    expect(r).toMatchObject({ isActive: false, changed: true, notified: { inApp: true, email: true } });
    expect(user.suspension.reason).toBe('Reported for selling unsafe food');
    expect(RefreshSession.deleteMany).toHaveBeenCalledWith({ user: user._id });
    expect(Business.updateMany).toHaveBeenCalledWith({ owner: user._id, isActive: true, deletedAt: null },
      { $set: { isActive: false, suspension: expect.objectContaining({ byOwner: true }) } });
    expect(Notification.create).toHaveBeenCalledWith(expect.objectContaining({ user: user._id, title: 'Your account was suspended', body: expect.stringContaining('Reported for selling unsafe food') }));
    expect(mails[0]).toMatchObject({ to: 'asha@example.com', subject: 'Your account was suspended' });
  });
  test('restoring brings back only the shops hidden because of the account, and tells them', async () => {
    user.isActive = false; user.suspension = { reason: 'x', at: new Date() };
    const r = await admin.setUserActive(user._id, true);
    expect(r).toMatchObject({ isActive: true, changed: true });
    expect(user.suspension).toBeUndefined();
    expect(Business.updateMany).toHaveBeenCalledWith({ owner: user._id, 'suspension.byOwner': true }, { $set: { isActive: true }, $unset: { suspension: 1 } });
    expect(Notification.create).toHaveBeenCalledWith(expect.objectContaining({ title: 'Your account was restored' }));
    expect(mails[0].subject).toBe('Your account was restored');
  });
  test('asking for the state they are already in does nothing and sends nothing', async () => {
    expect(await admin.setUserActive(user._id, true)).toMatchObject({ changed: false });
    user.isActive = false;
    expect(await admin.setUserActive(user._id, false, { reason: 'again' })).toMatchObject({ changed: false });
    expect(Notification.create).not.toHaveBeenCalled(); expect(mails).toHaveLength(0);
  });
  test('the administrator cannot be suspended; unknown members are 404', async () => {
    user.role = 'admin';
    await expect(admin.setUserActive(user._id, false, { reason: 'nope' })).rejects.toMatchObject({ statusCode: 403 });
    await expect(admin.setUserActive(oid(), false, { reason: 'nope' })).rejects.toMatchObject({ statusCode: 404 });
  });
  test('a failed email never fails the suspension', async () => {
    email.sendNoticeEmail.mockResolvedValue({ sent: false });
    expect(await admin.setUserActive(user._id, false, { reason: 'policy breach' })).toMatchObject({ isActive: false, notified: { inApp: true, email: false } });
  });
});

describe('shop suspend / restore', () => {
  test('suspending needs a reason, hides the shop, and notifies its owner (not another user)', async () => {
    await expect(admin.setBusinessActive(shop._id, false, {})).rejects.toMatchObject({ statusCode: 422 });
    const r = await admin.setBusinessActive(shop._id, false, { reason: 'Photos are not of this shop' });
    expect(r).toMatchObject({ isActive: false, changed: true });
    expect(shop.isActive).toBe(false);
    expect(shop.suspension).toMatchObject({ reason: 'Photos are not of this shop', byOwner: false });
    expect(Notification.create).toHaveBeenCalledWith(expect.objectContaining({ user: user._id, title: 'Asha Bakes was suspended' }));
    expect(mails[0]).toMatchObject({ to: 'asha@example.com' });
  });
  test('restoring clears the suspension and notifies; refused while the owner account is suspended', async () => {
    shop.isActive = false; shop.suspension = { reason: 'x', byOwner: false };
    owner.isActive = false;
    await expect(admin.setBusinessActive(shop._id, true)).rejects.toMatchObject({ statusCode: 409, code: 'OWNER_SUSPENDED' });
    owner.isActive = true;
    expect(await admin.setBusinessActive(shop._id, true)).toMatchObject({ isActive: true, changed: true });
    expect(shop.suspension).toBeUndefined();
    expect(Notification.create).toHaveBeenCalledWith(expect.objectContaining({ title: 'Asha Bakes was restored' }));
  });
  test('an unknown shop is 404 and already-in-state does nothing', async () => {
    Business.findOne.mockResolvedValueOnce(null);
    await expect(admin.setBusinessActive(oid(), false, { reason: 'abc' })).rejects.toMatchObject({ statusCode: 404 });
    expect(await admin.setBusinessActive(shop._id, true)).toMatchObject({ changed: false });
    expect(mails).toHaveLength(0);
  });
});

describe('notifications service', () => {
  test('saving never throws; reading and marking read are scoped to the caller', async () => {
    Notification.create.mockRejectedValueOnce(new Error('db down'));
    expect(await notifications.notify(user._id, { title: 't' })).toBeNull();
    const calls = [];
    jest.spyOn(Notification, 'updateMany').mockImplementation(async (f, u) => { calls.push([f, u]); return { modifiedCount: 2 }; });
    const me = oid(); const one = String(oid());
    expect(await notifications.markRead(me, undefined)).toEqual({ updated: 2 });
    await notifications.markRead(me, [one]);
    expect(calls[0][0]).toEqual({ user: me, isRead: false });
    expect(calls[1][0]).toEqual({ user: me, isRead: false, _id: { $in: [one] } });
  });
});

describe('notice email', () => {
  test('is HTML-escaped (a reason can never inject markup) and never throws without configuration', async () => {
    const html = email._noticeHtml({ heading: 'Hi', message: '<script>alert(1)</script>\nline two' });
    expect(html).not.toContain('<script>');
    expect(html).toContain('&lt;script&gt;');
    expect(html).toContain('line two');
    delete process.env.RESEND_API_KEY; delete process.env.RESEND_FROM_EMAIL; delete process.env.EMAIL_PROVIDER;
    email.sendNoticeEmail.mockRestore();
    expect(await email.sendNoticeEmail({ to: 'a@b.c', subject: 's', heading: 'h', message: 'm' })).toEqual({ sent: false });
    expect(await email.sendNoticeEmail({ to: undefined, subject: 's', heading: 'h', message: 'm' })).toEqual({ sent: false });
  });
});
