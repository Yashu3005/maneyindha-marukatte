const svc = require('../services/appDownload.service');
const { ok } = require('../utils/apiResponse');
const logger = require('../utils/logger');

exports.info = (_req, res, next) => {
  try {
    const info = svc.getDownloadInfo();
    if (!info.configured) logger.warn(`App download QR not available: ${info.problem}`);
    // `problem` names an env var, not a value; still, only expose the boolean to the public.
    res.set('Cache-Control', 'public, max-age=300');
    ok(res, info.configured ? info : { configured: false });
  } catch (e) { next(e); }
};

exports.qr = async (_req, res, next) => {
  try {
    const info = svc.getDownloadInfo();
    if (!info.configured) {
      return res.status(404).json({ success: false, error: { message: 'No app download link is configured', code: 'DOWNLOAD_NOT_CONFIGURED' } });
    }
    const png = await svc.renderQrPng(info.url);
    res.set({ 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=300', 'X-Content-Type-Options': 'nosniff' });
    res.send(png);
  } catch (e) { next(e); }
};
