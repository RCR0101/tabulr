/**
 * Minimal firebase-admin stand-in so index.js can be required in a unit test
 * without credentials or a network. Only the surface touched at module load
 * time (initializeApp, firestore and its statics) needs to exist.
 */
const noop = () => {};
const firestore = () => ({ collection: noop, doc: noop, runTransaction: noop });
firestore.FieldValue = { serverTimestamp: noop, increment: noop };
firestore.Timestamp = { now: noop, fromDate: noop };

module.exports = {
  initializeApp: noop,
  firestore,
  auth: () => ({ getUsers: noop, setCustomUserClaims: noop }),
};
