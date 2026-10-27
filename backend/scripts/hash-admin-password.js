#!/usr/bin/env node
// Creates the value for ADMIN_PASSWORD_HASH. The password is typed at a hidden prompt and is never printed or saved;
// only the salted hash is printed. Usage:  npm run admin:hash
const readline = require('readline');
const { hashPassword, MIN_LENGTH } = require('../src/utils/adminPassword');

function askHidden(question) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    const write = rl._writeToOutput;
    rl._writeToOutput = function mute(s) { if (s.includes(question)) write.call(rl, s); };
    rl.question(question, (answer) => { rl.close(); process.stdout.write('\n'); resolve(answer); });
  });
}

(async () => {
  const a = await askHidden(`New admin password (at least ${MIN_LENGTH} characters): `);
  if (a.length < MIN_LENGTH) { console.error(`Too short: use at least ${MIN_LENGTH} characters.`); process.exit(1); }
  const b = await askHidden('Type it again: ');
  if (a !== b) { console.error('The two entries do not match.'); process.exit(1); }
  const hash = await hashPassword(a);
  console.log('\nSet this as ADMIN_PASSWORD_HASH on the server (it is a secret; do not commit it):\n');
  console.log(hash);
  console.log('\nAlso set ADMIN_USERNAME to the username you want, then restart / redeploy the API.');
})();
