process.env.NODE_ENV = "test";

const test = require("node:test");
const assert = require("node:assert/strict");
const { __appointmentTest: helpers } = require("../index.js");

test("education scope keeps LGS and YKS mathematics teacher pools separate", () => {
  const lgsTeacher = {
    subjects: ["MATEMATİK"],
    teachingScopes: [{ level: "LGS", subject: "MATEMATİK" }],
  };
  assert.equal(helpers.teacherMatchesStudentScope(lgsTeacher, { className: "8/A" }, "MATEMATİK"), true);
  assert.equal(helpers.teacherMatchesStudentScope(lgsTeacher, { className: "11-A" }, "MATEMATİK"), false);
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
