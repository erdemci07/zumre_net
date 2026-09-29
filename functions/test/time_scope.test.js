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


test("study slots are filtered by the study guard education scope", () => {
  const schedule = {
    weeklySchedule: {
      monday: {
        studySlots: [
          { start: "14:00", end: "15:00", educationLevel: "LGS" },
          { start: "15:00", end: "16:00", educationLevel: "YKS" },
        ],
      },
    },
  };

  const lgsSlots = helpers.getStudySlots(schedule, "Mon", "LGS");
  const yksSlots = helpers.getStudySlots(schedule, "Mon", "YKS");

  assert.deepEqual(lgsSlots.map((slot) => slot.educationLevel), ["LGS"]);
  assert.deepEqual(yksSlots.map((slot) => slot.educationLevel), ["YKS"]);
});

test("legacy study guards remain dual-scope until admin narrows them", () => {
  assert.deepEqual(
    helpers.studyGuardEducationLevels({}),
    ["LGS", "YKS"]
  );
  assert.deepEqual(
    helpers.studyGuardEducationLevels({ educationLevels: ["LGS"] }),
    ["LGS"]
  );
});
