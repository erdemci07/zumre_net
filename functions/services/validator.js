const {
  cleanCell,
  makeEmailFromUsername,
  makeIdentityKey,
  normalizeText,
} = require("../utils/normalize");

const KNOWN_SUBJECTS = {
  MATEMATIK: "Matematik",
  FIZIK: "Fizik",
  KIMYA: "Kimya",
  BIYOLOJI: "Biyoloji",
  TURKCE: "Türkçe",
  TARIH: "Tarih",
  COGRAFYA: "Coğrafya",
  GEOMETRI: "Geometri",
  FEN: "Fen",
};

function getValue(row, mapping, field) {
  const index = mapping[field];

  if (index === undefined || index === null) {
    return "";
  }

  return cleanCell(row[index]);
}

function splitFullName(value) {
  const parts = cleanCell(value).split(/\s+/).filter(Boolean);

  if (parts.length <= 1) {
    return {
      name: cleanCell(value),
      surname: "",
      fullName: cleanCell(value),
    };
  }

  return {
    name: parts[0],
    surname: parts.slice(1).join(" "),
    fullName: parts.join(" "),
  };
}

function detectSubject(value) {
  const normalized = normalizeText(value);
  return KNOWN_SUBJECTS[normalized] || "";
}

function validateRows(rows, mapping, type) {
  const validRows = [];
  const invalidRows = [];

  rows.forEach((row, rowIndex) => {
    let name = getValue(row, mapping, "name");
    let surname = getValue(row, mapping, "surname");
    const username = getValue(row, mapping, "username");
    const password = getValue(row, mapping, "password");

    const className = getValue(row, mapping, "className");
    const branch = getValue(row, mapping, "branch");
    const studentNo = getValue(row, mapping, "studentNo");
    const department = getValue(row, mapping, "department");
    const subjectsRaw = getValue(row, mapping, "subjects");

    let subjects = subjectsRaw
      ? subjectsRaw
          .split(/[|,;/]+/)
          .map((s) => cleanCell(s))
          .filter(Boolean)
      : [];

    if (type === "teacher") {
      const subjectFromSurname = detectSubject(surname);

      if (subjectFromSurname) {
        subjects = [subjectFromSurname];
        surname = "";
      }

      if (!surname && name.includes(" ")) {
        const split = splitFullName(name);
        name = split.fullName;
        surname = "";
      }
    }

    const errors = [];

    if (!name) errors.push("Ad boş");
    if (!username) errors.push("Kullanıcı adı boş");
    if (!password) errors.push("Şifre boş");

    if (type === "student") {
      if (!surname) errors.push("Soyad boş");
      if (!className) errors.push("Sınıf boş");
      if (!branch) errors.push("Şube boş");
    }

    if (type === "teacher") {
      if (subjects.length === 0) {
        errors.push("Branş/Ders bilgisi bulunamadı");
      }
    }

    const fullName =
      type === "teacher"
        ? name.trim()
        : `${name} ${surname}`.trim();

    const identityKey = makeIdentityKey(username);
    const email = makeEmailFromUsername(username);

    const normalized = {
      type,
      role: type === "teacher" ? "teacher" : "student",
      name,
      surname,
      fullName,
      username,
      identityKey,
      email,
      password,
      className,
      branch,
      department,
      studentNo,
      subjects,
    };

    if (errors.length > 0) {
      invalidRows.push({
        rowNumber: rowIndex + 2,
        errors,
        raw: row,
        normalized,
      });
    } else {
      validRows.push({
        rowNumber: rowIndex + 2,
        raw: row,
        normalized,
      });
    }
  });

  return {
    validRows,
    invalidRows,
  };
}

module.exports = {
  validateRows,
};