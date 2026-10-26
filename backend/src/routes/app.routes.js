const router = require('express').Router();
const ctrl = require('../controllers/app.controller');

router.get('/download', ctrl.info);
router.get('/download-qr.png', ctrl.qr);

module.exports = router;
