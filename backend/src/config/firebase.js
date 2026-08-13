const admin = require('firebase-admin');

let initialized = false;

function getFirebase() {
  if (!initialized) {
    if (!process.env.FIREBASE_PROJECT_ID) {
      throw new Error('Firebase env vars not set (FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY)');
    }
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        // Vercel/hosts store the key with literal \n — restore real newlines.
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      }),
    });
    initialized = true;
  }
  return admin;
}

module.exports = { getFirebase };
