const AppError = require('../utils/AppError');

// Provider problems are reported to the client in generic terms; details go to the server log only.
const aiError = (message, status, code) => new AppError(message, status, code);
exports.notConfigured = (what) => aiError(`AI is not configured (${what})`, 503, 'AI_NOT_CONFIGURED');
exports.timeout = () => aiError('The AI service took too long. Please try again.', 504, 'AI_TIMEOUT');
exports.busy = () => aiError('The AI service is busy. Please try again shortly.', 503, 'AI_RATE_LIMITED');
exports.upstream = () => aiError('The AI service could not complete the request. Please try again.', 502, 'AI_PROVIDER_ERROR');
// `why` is a short non-sensitive reason code (e.g. MAX_TOKENS) so a failure can be diagnosed from the screen alone.
exports.badOutput = (why) => aiError(`The AI service returned an unusable answer. Please try again.${why ? ` (${why})` : ''}`, 502, 'AI_BAD_OUTPUT');
