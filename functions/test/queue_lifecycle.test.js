process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");
const { __appointmentTest: helpers } = require("../index.js");

function fakeTimestamp(date) {
  return {
    toDate: () => date,
  };
}

const scheduleData = {
  weeklySchedule: {
    tuesday: {
      closed: false,
      zumreClosed: false,
      zumreSlots: [
        { start: "16:00", end: "17:00", educationLevel: "LGS" },
        { start: "17:00", end: "18:00", educationLevel: "YKS" },
      ],
      studySlots: [],
    },
  },
};

const teacherData = {
  role: "teacher",
  teacherStatus: "available",
  subjects: ["MATEMATİK"],
  teachingScopes: [
    { level: "LGS", subject: "MATEMATİK" },
    { level: "YKS", subject: "MATEMATİK" },
  ],
  weeklyAvailability: {
    tuesday: [
      { start: "16:00", end: "18:00", educationLevel: "BOTH" },
    ],
  },
};

test("queue start gate respects the queue's own LGS/YKS slot", () => {
  const now = new Date("2099-09-15T17:15:00+03:00");

  const lgsReason = helpers.queueStartBlockReason({
    scheduleData,
    runtimeData: { institutionMode: "active" },
    queueData: {
      subject: "MATEMATİK",
      educationLevel: "LGS",
    },
    teacherData,
    studentData: {
      role: "student",
      educationLevel: "LGS",
      isInStudySession: false,
    },
    now,
  });

  const yksReason = helpers.queueStartBlockReason({
    scheduleData,
    runtimeData: { institutionMode: "active" },
    queueData: {
      subject: "MATEMATİK",
      educationLevel: "YKS",
    },
    teacherData,
    studentData: {
      role: "student",
      educationLevel: "YKS",
      isInStudySession: false,
    },
    now,
  });

  assert.equal(lgsReason, "Öğrencinin zümre saati şu anda aktif değil.");
  assert.equal(yksReason, null);
});

test("LGS queue times out even while a YKS slot is still open", () => {
  const queueData = {
    educationLevel: "LGS",
    startedAt: fakeTimestamp(
      new Date("2099-09-15T16:30:00+03:00")
    ),
  };

  assert.equal(
    helpers.shouldAutoCompleteZumreQueue(
      queueData,
      scheduleData,
      new Date("2099-09-15T17:16:00+03:00")
    ),
    true
  );
});

test("legacy queue scope can still be inferred from student data", () => {
  assert.equal(
    helpers.queueEducationLevel(
      { subject: "MATEMATİK" },
      { className: "DERSLİK 8" }
    ),
    "LGS"
  );
});
