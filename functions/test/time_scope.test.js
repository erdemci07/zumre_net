process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");
const { __appointmentTest: helpers } = require("../index.js");

test("LGS and YKS time blocks are isolated while legacy blocks remain available", () => {
  assert.equal(
    helpers.timeSlotMatchesEducationScope({ educationLevel: "LGS" }, "LGS"),
    true
  );
  assert.equal(
    helpers.timeSlotMatchesEducationScope({ educationLevel: "LGS" }, "YKS"),
    false
  );
  assert.equal(helpers.timeSlotMatchesEducationScope({}, null), true);
});

test("LGS-only teacher cannot save YKS availability", () => {
  const error = helpers.validateTeacherWeeklyAvailability(
    {
      teachingScopes: [{ level: "LGS", subject: "MATEMATİK" }],
    },
    {
      monday: [{ start: "14:20", end: "15:00", educationLevel: "YKS" }],
    }
  );

  assert.equal(error, "Öğretmenin eğitim kapsamı seçilen zaman bloğuyla uyumlu değil.");
});

test("teacher availability detects real interval overlap but not touching intervals", () => {
  const teacher = { teachingScopes: [] };
  const overlap = helpers.validateTeacherWeeklyAvailability(teacher, {
    monday: [
      { start: "14:20", end: "15:00", educationLevel: "LGS" },
      { start: "14:40", end: "15:20", educationLevel: "YKS" },
    ],
  });
  const touching = helpers.validateTeacherWeeklyAvailability(teacher, {
    monday: [
      { start: "14:20", end: "15:00", educationLevel: "LGS" },
      { start: "15:00", end: "15:40", educationLevel: "YKS" },
    ],
  });

  assert.equal(
    overlap,
    "Bu öğretmenin seçilen saat aralığında başka bir programı bulunuyor."
  );
  assert.equal(touching, null);
});
