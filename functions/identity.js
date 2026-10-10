// The users/{id} document id for a BITS email: the local part plus a campus
// letter. Mirrors userDocId() in firestore.rules and AuthService.deriveUserDocId.
function deriveUserDocId(email) {
  if (!email || !email.includes("@")) return null;
  const [username, domain] = email.split("@");
  const d = domain.toLowerCase();
  if (d === "hyderabad.bits-pilani.ac.in") return `${username}H`;
  if (d === "pilani.bits-pilani.ac.in") return `${username}P`;
  if (d === "goa.bits-pilani.ac.in") return `${username}G`;
  if (d === "dubai.bits-pilani.ac.in") return `${username}D`;
  return null;
}

module.exports = { deriveUserDocId };
