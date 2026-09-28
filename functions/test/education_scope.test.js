process.env.NODE_ENV = "test";

const test = require("node:test");
const assert = require("node:assert/strict");
const { __appointmentTest: helpers } = require("../index.js");

test("production className prefixes keep LGS and YKS mathematics pools separate", () => {
  const lgsTeacher = {
    subjects: ["MATEMATİK"],
    teachingScopes: [{ level: "LGS", subject: "MATEMATİK" }],
  };
  const yksTeacher = {
    subjects: ["MATEMATİK"],
    teachingScopes: [{ level: "YKS", subject: "MATEMATİK" }],
  };

  for (const className of ["6-DERSLİK 6", "8-DERSLİK 9"]) {
    const student = { className };
    assert.equal(helpers.studentEducationLevel(student), "LGS");
    assert.equal(helpers.teacherMatchesStudentScope(lgsTeacher, student, "MATEMATİK"), true);
    assert.equal(helpers.teacherMatchesStudentScope(yksTeacher, student, "MATEMATİK"), false);
  }

  for (const className of ["10-DERSLİK 6", "11-DERSLİK 4 SAY", "12-DERSLİK 13 EA", "MEZUN-DERSLİK 10"]) {
    const student = { className };
    assert.equal(helpers.studentEducationLevel(student), "YKS");
    assert.equal(helpers.teacherMatchesStudentScope(lgsTeacher, student, "MATEMATİK"), false);
    assert.equal(helpers.teacherMatchesStudentScope(yksTeacher, student, "MATEMATİK"), true);
  }

  const unknownLevelStudent = { className: "DERSLİK-16-SÖZEL" };
  assert.equal(helpers.studentEducationLevel(unknownLevelStudent), null);
  assert.equal(helpers.teacherMatchesStudentScope(lgsTeacher, unknownLevelStudent, "MATEMATİK"), false);
  assert.equal(helpers.teacherMatchesStudentScope(yksTeacher, unknownLevelStudent, "MATEMATİK"), false);
});

test("dual-scope and legacy teachers remain available as intended", () => {
  const dualTeacher = {
    subjects: ["MATEMATİK"],
    teachingScopes: [
      { level: "LGS", subject: "MATEMATİK" },
      { level: "YKS", subject: "MATEMATİK" },
    ],
  };
  assert.equal(helpers.teacherMatchesStudentScope(dualTeacher, { educationLevel: "LGS" }, "MATEMATİK"), true);
  assert.equal(helpers.teacherMatchesStudentScope(dualTeacher, { educationLevel: "YKS" }, "MATEMATİK"), true);
  assert.equal(helpers.teacherMatchesStudentScope({ subjects: ["MATEMATİK"] }, { educationLevel: "LGS" }, "MATEMATİK"), true);
});
