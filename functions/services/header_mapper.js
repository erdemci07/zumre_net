const {
  STUDENT_FIELD_ALIASES,
  TEACHER_FIELD_ALIASES,
} = require("../utils/constants");

const { normalizeText } = require("../utils/normalize");

function findMatchingField(normalizedHeader, aliases) {
  for (const [fieldName, possibleHeaders] of Object.entries(aliases)) {
    const normalizedAliases = possibleHeaders.map((h) => normalizeText(h));

    if (normalizedAliases.includes(normalizedHeader)) {
      return fieldName;
    }
  }

  return null;
}

function mapHeaders(rawHeaders, type) {
  const aliases =
    type === "teacher" ? TEACHER_FIELD_ALIASES : STUDENT_FIELD_ALIASES;

  const mapping = {};
  const unknownHeaders = [];

  rawHeaders.forEach((header, index) => {
    const normalizedHeader = normalizeText(header);
    const matchedField = findMatchingField(normalizedHeader, aliases);

    if (matchedField) {
      mapping[matchedField] = index;
    } else {
      unknownHeaders.push({
        index,
        original: header,
        normalized: normalizedHeader,
      });
    }
  });

  return {
    mapping,
    unknownHeaders,
  };
}

function hasRequiredFields(mapping, type) {
  const required =
    type === "teacher"
      ? ["name", "surname", "username", "password", "subjects"]
      : ["name", "surname", "username", "password", "className"];

  const missing = required.filter((field) => mapping[field] === undefined);

  return {
    ok: missing.length === 0,
    missing,
  };
}

module.exports = {
  mapHeaders,
  hasRequiredFields,
};