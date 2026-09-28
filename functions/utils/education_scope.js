const EDUCATION_LEVELS = ["LGS", "YKS"];

function cleanText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function normalizeSubject(value) {
  return cleanText(value)
    .toLocaleLowerCase("tr-TR")
    .replace(/ı/g, "i")
    .replace(/ş/g, "s")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c");
}

function educationLevel(value) {
  const level = cleanText(value).toUpperCase();
  return EDUCATION_LEVELS.includes(level) ? level : null;
}

function studentEducationLevel(student = {}) {
  const explicit = educationLevel(student.educationLevel);
  if (explicit) return explicit;
  const className = cleanText(student.className).toLocaleUpperCase("tr-TR");
  if (/^(5|6|7|8)-/.test(className)) return "LGS";
  if (/^(9|10|11|12)-/.test(className) || /^MEZUN(?:-|$)/.test(className)) {
    return "YKS";
  }
  return null;
}

function teachingScopes(teacher = {}) {
  if (!Array.isArray(teacher.teachingScopes)) return [];
  const seen = new Set();
  return teacher.teachingScopes.reduce((result, scope) => {
    const level = educationLevel(scope?.level);
    const subject = cleanText(scope?.subject);
    const key = `${level}|${normalizeSubject(subject)}`;
    if (level && subject && !seen.has(key)) {
      seen.add(key);
      result.push({ level, subject });
    }
    return result;
  }, []);
}

function teacherMatchesEducationScope(teacher, level, subject) {
  const scopes = teachingScopes(teacher);
  if (scopes.length === 0) return true;
  if (!level) return false;
  return scopes.some((scope) =>
    scope.level === level && normalizeSubject(scope.subject) === normalizeSubject(subject)
  );
}

module.exports = {
  EDUCATION_LEVELS,
  educationLevel,
  studentEducationLevel,
  teachingScopes,
  teacherMatchesEducationScope,
};
