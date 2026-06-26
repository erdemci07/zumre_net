function normalizeText(value) {
  if (value === undefined || value === null) return "";

  return String(value)
    .trim()
    .toUpperCase()
    .replace(/İ/g, "I")
    .replace(/İ/g, "I")
    .replace(/Ğ/g, "G")
    .replace(/Ü/g, "U")
    .replace(/Ş/g, "S")
    .replace(/Ö/g, "O")
    .replace(/Ç/g, "C")
    .replace(/\*/g, "")
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function cleanCell(value) {
  if (value === undefined || value === null) return "";
  return String(value).trim();
}

function makeEmailFromUsername(username) {
  const cleanUsername = cleanCell(username)
    .replace(/\s+/g, "")
    .toLowerCase();

  return `${cleanUsername}@zumrenet.local`;
}

function makeIdentityKey(username) {
  return cleanCell(username).replace(/\s+/g, "");
}

module.exports = {
  normalizeText,
  cleanCell,
  makeEmailFromUsername,
  makeIdentityKey,
};