const EDUCATION_LEVELS = ["LGS", "YKS"];
const TIME_SLOT_SCOPES = ["LGS", "YKS", "BOTH"];

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

  const classText = [
    student.className,
    student.class,
    student.grade,
    student.branch,
    student.department,
  ]
    .filter((value) => value !== undefined && value !== null)
    .map((value) => cleanText(value))
    .filter(Boolean)
    .join(" ")
    .toLocaleUpperCase("tr-TR");

  if (/(^|\W)MEZUN(?=\W|$)/.test(classText)) return "YKS";

  const gradeMatch = /(^|\D)(1[0-2]|[5-9])(?=\D|$)/.exec(classText);
  const grade = Number(gradeMatch?.[2]);
  if (Number.isInteger(grade) && grade >= 5 && grade <= 8) return "LGS";
  if (Number.isInteger(grade) && grade >= 9 && grade <= 12) return "YKS";
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

function timeSlotScope(slot = {}) {
  const scope = cleanText(slot.educationLevel || slot.scope).toUpperCase();
  return TIME_SLOT_SCOPES.includes(scope) ? scope : "BOTH";
}

function timeSlotMatchesEducationScope(slot, level) {
  const scope = timeSlotScope(slot);
  return scope === "BOTH" || (!!level && scope === level);
}

// Institution schedules existed before scope metadata. Legacy/BOTH schedule
// slots are the existing YKS program; an LGS schedule must be explicit.
function institutionScheduleScope(slot = {}) {
  return timeSlotScope(slot) === "LGS" ? "LGS" : "YKS";
}

function teacherCanUseTimeSlotScope(teacher = {}, scope) {
  const normalizedScope = timeSlotScope({ educationLevel: scope });
  const scopes = teachingScopes(teacher);
  if (scopes.length === 0) return true;
  const levels = new Set(scopes.map((item) => item.level));
  return normalizedScope === "BOTH"
    ? levels.has("LGS") && levels.has("YKS")
    : levels.has(normalizedScope);
}

module.exports = {
  EDUCATION_LEVELS,
  educationLevel,
  studentEducationLevel,
  teachingScopes,
  teacherMatchesEducationScope,
  timeSlotScope,
  timeSlotMatchesEducationScope,
  institutionScheduleScope,
  teacherCanUseTimeSlotScope,
};
