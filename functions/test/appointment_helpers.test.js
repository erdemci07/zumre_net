process.env.NODE_ENV = "test";

const assert = require("node:assert/strict");
const test = require("node:test");

const { __appointmentTest: helpers } = require("../index.js");

function fakeDoc(data) {
  return {
    id: data.id || "doc-a",
    data: () => data,
  };
}

function fakeTeacherDoc(id, data) {
  return {
    id,
    exists: true,
    data: () => ({
      role: "teacher",
      subjects: ["MATEMATİK"],
      weeklyAvailability: {
        tuesday: [{ start: "16:30", end: "17:10" }],
      },
      ...data,
    }),
  };
}

function fakeTimestamp(date) {
  return {
    toDate: () => date,
  };
}

function fakeNoShowDoc(id, data) {
  const updates = [];
  return {
    id,
    data: () => data,
    ref: {
      update: async (payload) => {
        updates.push(payload);
      },
    },
    updates,
  };
}

test("question count maps to existing estimated minutes", () => {
  assert.equal(helpers.estimatedMinutesForQuestionCount(1), 4);
  assert.equal(helpers.estimatedMinutesForQuestionCount(2), 7);
  assert.equal(helpers.estimatedMinutesForQuestionCount(3), 10);
  assert.equal(helpers.estimatedMinutesForQuestionCount(4), 13);
});

test("appointment id is deterministic per student and idempotency key", () => {
  const first = helpers.appointmentIdFor("student-a", "tap-1");
  const second = helpers.appointmentIdFor("student-a", "tap-1");
  const different = helpers.appointmentIdFor("student-a", "tap-2");

  assert.equal(first, second);
  assert.notEqual(first, different);
});

test("same idempotency key requires the same booking identity", () => {
  const scheduledStart = new Date("2099-09-15T16:30:00+03:00");
  const existing = {
    studentId: "student-a",
    teacherId: "teacher-a",
    subject: "MATEMATİK",
    questionCount: 1,
    dateKey: "2099-09-15",
    scheduledStart: fakeTimestamp(scheduledStart),
  };

  assert.equal(
    helpers.appointmentMatchesBookingIdentity(existing, {
      studentId: "student-a",
      teacherId: "teacher-a",
      subject: "MATEMATİK",
      questionCount: 1,
      dateKey: "2099-09-15",
      scheduledStart,
    }),
    true
  );

  assert.equal(
    helpers.appointmentMatchesBookingIdentity(existing, {
      studentId: "student-a",
      teacherId: "teacher-b",
      subject: "COĞRAFYA",
      questionCount: 1,
      dateKey: "2099-09-15",
      scheduledStart,
    }),
    false
  );
});

test("configured zumre slot must fully contain the appointment", () => {
  const scheduleData = {
    weeklySchedule: {
      tuesday: {
        closed: false,
        zumreSlots: [{ start: "16:30", end: "17:10" }],
      },
    },
  };
  const start = new Date("2099-09-15T16:30:00+03:00");
  const end = new Date("2099-09-15T16:40:00+03:00");
  const outsideEnd = new Date("2099-09-15T17:15:00+03:00");

  assert.equal(
    helpers.findContainingZumreSlot(scheduleData, start, end).start,
    "16:30"
  );
  assert.equal(
    helpers.findContainingZumreSlot(scheduleData, start, outsideEnd),
    null
  );
});

test("teacher overlap blocks generated start options", () => {
  const slot = {
    start: "16:30",
    end: "17:10",
    startMinutes: 990,
    endMinutes: 1030,
  };
  const existing = fakeDoc({
    slotKey: helpers.buildSlotKey("2099-09-15", slot),
    estimatedMinutes: 10,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:40:00+03:00")),
  });

  const options = helpers.generateAppointmentStartOptions({
    dateKey: "2099-09-15",
    slot,
    durationMinutes: 4,
    teacherAppointmentDocs: [existing],
    studentAppointmentDocs: [],
  });

  assert.equal(options.some((item) => item.start === "16:30"), false);
  assert.equal(options.some((item) => item.start === "16:40"), true);
});

test("student transition buffer blocks too-close adjacent appointments", () => {
  const slot = {
    start: "16:30",
    end: "17:10",
    startMinutes: 990,
    endMinutes: 1030,
  };
  const existing = fakeDoc({
    slotKey: helpers.buildSlotKey("2099-09-15", slot),
    estimatedMinutes: 4,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  });

  assert.equal(
    helpers.appointmentOverlapsDocs(
      [existing],
      new Date("2099-09-15T16:35:00+03:00"),
      new Date("2099-09-15T16:39:00+03:00"),
      { bufferMinutes: helpers.APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES }
    ),
    true
  );
  assert.equal(
    helpers.appointmentOverlapsDocs(
      [existing],
      new Date("2099-09-15T16:36:00+03:00"),
      new Date("2099-09-15T16:40:00+03:00"),
      { bufferMinutes: helpers.APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES }
    ),
    false
  );
});

test("planned capacity uses 65 percent of actual slot duration", () => {
  const slot = {
    startMinutes: 990,
    endMinutes: 1030,
  };

  assert.equal(helpers.plannedCapacityMinutesForSlot(slot), 26);
});

test("capacity excludes other slots and cancelled appointments", () => {
  const slotKey = "2099-09-15-16:30-17:10";
  const usedDocs = [
    fakeDoc({
      status: "scheduled",
      slotKey,
      estimatedMinutes: 13,
    }),
    fakeDoc({
      status: "scheduled",
      slotKey,
      estimatedMinutes: 10,
    }),
    fakeDoc({
      status: "cancelled",
      slotKey,
      estimatedMinutes: 13,
    }),
    fakeDoc({
      status: "scheduled",
      slotKey: "2099-09-15-17:20-18:00",
      estimatedMinutes: 13,
    }),
  ];

  assert.equal(helpers.appointmentMinutesInSlot(usedDocs, slotKey), 23);
  assert.equal(23 + 4 > 26, true);
});

test("teacher no-show metadata starts as pending verification", () => {
  const verified = helpers.noShowVerificationUpdate({
    verified: true,
    reason: "queue_activity",
  });
  const unverified = helpers.noShowVerificationUpdate({ verified: false });

  assert.equal(verified.noShowVerificationStatus, "verified");
  assert.equal(verified.noShowVerificationReason, "queue_activity");
  assert.equal(unverified.noShowVerificationStatus, "unverified");
  assert.equal(unverified.noShowVerificationReason, null);
});

test("appointment ending after slot end is not offered", () => {
  const slot = {
    start: "16:30",
    end: "17:10",
    startMinutes: 990,
    endMinutes: 1030,
  };

  const options = helpers.generateAppointmentStartOptions({
    dateKey: "2099-09-15",
    slot,
    durationMinutes: 13,
    teacherAppointmentDocs: [],
    studentAppointmentDocs: [],
  });

  assert.equal(options.some((item) => item.start === "17:00"), false);
  assert.equal(options.at(-1).start, "16:55");
});

test("Europe/Istanbul date key is derived from Istanbul local date", () => {
  assert.equal(
    helpers.dateKeyFromIstanbulDate(new Date("2099-09-14T21:30:00Z")),
    "2099-09-15"
  );
});

test("scheduled appointment can start only while due", () => {
  const dueAppointment = {
    status: "scheduled",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:40:00+03:00")),
  };

  assert.equal(
    helpers.appointmentCanBecomeLive(
      dueAppointment,
      new Date("2099-09-15T16:31:00+03:00")
    ).ok,
    true
  );
  assert.equal(
    helpers.appointmentCanBecomeLive(
      dueAppointment,
      new Date("2099-09-15T16:29:00+03:00")
    ).ok,
    false
  );
  assert.equal(
    helpers.appointmentCanBecomeLive(
      dueAppointment,
      new Date("2099-09-15T16:40:00+03:00")
    ).ok,
    false
  );
});

test("no-show uses the same due gate and rejects already started", () => {
  const startedAppointment = {
    status: "started",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:40:00+03:00")),
  };

  assert.equal(
    helpers.appointmentCanBecomeLive(
      startedAppointment,
      new Date("2099-09-15T16:31:00+03:00")
    ).ok,
    false
  );
});

test("linked queue id is deterministic for double start protection", () => {
  const first = helpers.appointmentLinkedQueueId("appointment-a");
  const second = helpers.appointmentLinkedQueueId("appointment-a");

  assert.equal(first, second);
});

test("appointment linked queue fields match student queue listener contract", () => {
  const appointmentData = {
    studentId: "student-a",
    studentName: "HASAN KAYA",
    teacherId: "teacher-a",
    teacherName: "BARAN HOCA",
    subject: "MATEMATİK",
    questionCount: 2,
    estimatedMinutes: 7,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:37:00+03:00")),
  };

  const queueData = helpers.buildAppointmentLinkedQueueData(
    "appointment-a",
    appointmentData,
    new Date("2099-09-15T16:30:00+03:00")
  );

  assert.equal(queueData.studentId, "student-a");
  assert.equal(queueData.teacherId, "teacher-a");
  assert.equal(queueData.status, "in_progress");
  assert.equal(queueData.source, "appointment");
  assert.equal(queueData.appointmentId, "appointment-a");
  assert.equal(queueData.questionCount, 2);
  assert.equal(queueData.estimatedMinutes, 7);
  assert.equal(queueData.extraMinutes, 0);
});

test("appointment linked queue uses fresh queue createdAt semantics", () => {
  const appointmentData = {
    studentId: "student-a",
    studentName: "HASAN KAYA",
    teacherId: "teacher-a",
    teacherName: "BARAN HOCA",
    subject: "MATEMATİK",
    questionCount: 1,
    estimatedMinutes: 4,
    createdAt: fakeTimestamp(new Date("2099-09-01T10:00:00+03:00")),
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };

  const queueData = helpers.buildAppointmentLinkedQueueData(
    "appointment-a",
    appointmentData,
    new Date("2099-09-15T16:30:00+03:00")
  );

  assert.notEqual(queueData.createdAt, appointmentData.createdAt);
  assert.equal(queueData.appointmentScheduledStart, appointmentData.scheduledStart);
});

test("future scheduled appointment can be transferred or cancelled", () => {
  const appointment = {
    status: "scheduled",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };

  assert.equal(
    helpers.appointmentIsFutureScheduled(
      appointment,
      new Date("2099-09-15T16:00:00+03:00")
    ).ok,
    true
  );
});

test("started appointment cannot be cancelled or transferred", () => {
  const appointment = {
    status: "started",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };

  assert.equal(
    helpers.appointmentIsFutureScheduled(
      appointment,
      new Date("2099-09-15T16:00:00+03:00")
    ).ok,
    false
  );
});

test("due appointment cannot use future transfer UI path", () => {
  const appointment = {
    status: "scheduled",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };

  assert.equal(
    helpers.appointmentIsFutureScheduled(
      appointment,
      new Date("2099-09-15T16:30:00+03:00")
    ).ok,
    false
  );
});

test("transfer edit window is capped at 15 minutes", () => {
  const appointment = {
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
  };
  const editUntil = helpers.transferEditUntilFor(
    appointment,
    new Date("2099-09-15T16:00:00+03:00")
  );

  assert.equal(editUntil.toISOString(), new Date("2099-09-15T16:15:00+03:00").toISOString());
});

test("transfer edit window is capped by scheduled start", () => {
  const appointment = {
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:10:00+03:00")),
  };
  const editUntil = helpers.transferEditUntilFor(
    appointment,
    new Date("2099-09-15T16:00:00+03:00")
  );

  assert.equal(editUntil.toISOString(), new Date("2099-09-15T16:10:00+03:00").toISOString());
});

test("transfer keeps appointment scheduled and does not create queue data", () => {
  const appointment = {
    status: "scheduled",
    teacherId: "teacher-a",
    teacherName: "A HOCA",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };

  assert.equal(appointment.status, "scheduled");
  assert.equal(helpers.appointmentLinkedQueueId("appointment-a"), "appointment_appointment-a");
});

test("manual transfer rejects wrong subject destination", () => {
  const appointment = {
    subject: "MATEMATİK",
    dateKey: "2099-09-15",
    questionCount: 1,
    estimatedMinutes: 4,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };
  const destination = fakeTeacherDoc("teacher-b", {
    subjects: ["FİZİK"],
  });

  const result = helpers.appointmentTransferEligibility({
    appointmentId: "appointment-a",
    appointmentData: appointment,
    destinationTeacherDoc: destination,
    dateAppointmentDocs: [],
    studyDutyDocs: [],
    scheduleData: {
      weeklySchedule: {
        tuesday: {
          closed: false,
          zumreSlots: [{ start: "16:30", end: "17:10" }],
        },
      },
    },
    runtimeData: {},
  });

  assert.equal(result.ok, false);
});

test("transfer rejects destination overlap", () => {
  const appointment = {
    subject: "MATEMATİK",
    dateKey: "2099-09-15",
    questionCount: 1,
    estimatedMinutes: 4,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  };
  const existing = fakeDoc({
    id: "appointment-b",
    teacherId: "teacher-b",
    status: "scheduled",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
  });

  const result = helpers.appointmentTransferEligibility({
    appointmentId: "appointment-a",
    appointmentData: appointment,
    destinationTeacherDoc: fakeTeacherDoc("teacher-b", {}),
    dateAppointmentDocs: [existing],
    studyDutyDocs: [],
    scheduleData: {
      weeklySchedule: {
        tuesday: {
          closed: false,
          zumreSlots: [{ start: "16:30", end: "17:10" }],
        },
      },
    },
    runtimeData: {},
  });

  assert.equal(result.ok, false);
});

test("transfer rejects destination capacity full", () => {
  const slot = { start: "16:30", end: "17:10" };
  const appointment = {
    subject: "MATEMATİK",
    dateKey: "2099-09-15",
    questionCount: 1,
    estimatedMinutes: 4,
    scheduledStart: fakeTimestamp(new Date("2099-09-15T17:00:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T17:04:00+03:00")),
  };
  const usedDocs = [
    fakeDoc({
      id: "appointment-b",
      teacherId: "teacher-b",
      status: "scheduled",
      slotKey: "2099-09-15-16:30-17:10",
      estimatedMinutes: 13,
      scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:43:00+03:00")),
    }),
    fakeDoc({
      id: "appointment-c",
      teacherId: "teacher-b",
      status: "scheduled",
      slotKey: "2099-09-15-16:30-17:10",
      estimatedMinutes: 10,
      scheduledStart: fakeTimestamp(new Date("2099-09-15T16:45:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:55:00+03:00")),
    }),
  ];

  const result = helpers.appointmentTransferEligibility({
    appointmentId: "appointment-a",
    appointmentData: appointment,
    destinationTeacherDoc: fakeTeacherDoc("teacher-b", {}),
    dateAppointmentDocs: usedDocs,
    studyDutyDocs: [],
    scheduleData: {
      weeklySchedule: {
        tuesday: {
          closed: false,
          zumreSlots: [slot],
        },
      },
    },
    runtimeData: {},
  });

  assert.equal(result.ok, false);
});

test("transfer edit requester is allowed only before editUntil and start", () => {
  const appointment = {
    teacherId: "teacher-b",
    transferredFromTeacherId: "teacher-a",
    transferEditUntil: fakeTimestamp(new Date("2099-09-15T16:15:00+03:00")),
    scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
  };

  assert.equal(
    helpers.canRequesterTransferAppointment(
      appointment,
      { uid: "teacher-a" },
      new Date("2099-09-15T16:10:00+03:00")
    ),
    true
  );
  assert.equal(
    helpers.canRequesterTransferAppointment(
      appointment,
      { uid: "teacher-a" },
      new Date("2099-09-15T16:16:00+03:00")
    ),
    false
  );
});

test("TYT and AYT planned exam durations match institution rules", () => {
  assert.equal(helpers.plannedExamDurationMinutes("tyt"), 165);
  assert.equal(helpers.plannedExamDurationMinutes("ayt"), 180);
  assert.equal(helpers.plannedExamDurationMinutes("unknown"), 0);
});

test("planned exam conflict helper detects overlapping appointment interval", () => {
  const plannedExam = {
    status: "scheduled",
    examType: "tyt",
    scheduledStart: fakeTimestamp(new Date("2099-09-15T10:00:00+03:00")),
    scheduledEnd: fakeTimestamp(new Date("2099-09-15T12:45:00+03:00")),
  };

  assert.equal(
    helpers.plannedExamConflictsWithAppointment(
      plannedExam,
      new Date("2099-09-15T12:40:00+03:00"),
      new Date("2099-09-15T12:50:00+03:00")
    ),
    true
  );
  assert.equal(
    helpers.plannedExamConflictsWithAppointment(
      plannedExam,
      new Date("2099-09-15T12:45:00+03:00"),
      new Date("2099-09-15T12:55:00+03:00")
    ),
    false
  );
});

test("schedule conflict detects only future scheduled appointments invalidated by changed slot", () => {
  const oldScheduleData = {
    weeklySchedule: {
      tuesday: {
        closed: false,
        zumreSlots: [{ start: "16:30", end: "17:10" }],
        studySlots: [],
      },
    },
  };
  const newWeeklySchedule = {
    monday: { closed: false, zumreSlots: [], studySlots: [] },
    tuesday: {
      closed: false,
      zumreSlots: [{ start: "17:20", end: "18:00" }],
      studySlots: [],
    },
    wednesday: { closed: false, zumreSlots: [], studySlots: [] },
    thursday: { closed: false, zumreSlots: [], studySlots: [] },
    friday: { closed: false, zumreSlots: [], studySlots: [] },
    saturday: { closed: false, zumreSlots: [], studySlots: [] },
    sunday: { closed: false, zumreSlots: [], studySlots: [] },
  };
  const docs = [
    fakeDoc({
      id: "future-invalid",
      status: "scheduled",
      scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
    }),
    fakeDoc({
      id: "completed-ignored",
      status: "completed",
      scheduledStart: fakeTimestamp(new Date("2099-09-15T16:30:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T16:34:00+03:00")),
    }),
  ];

  const conflicts = helpers.scheduleConflictDocsForChange({
    appointmentDocs: docs,
    oldScheduleData,
    newWeeklySchedule,
    now: new Date("2099-09-15T09:00:00+03:00"),
  });

  assert.equal(conflicts.length, 1);
  assert.equal(conflicts[0].id, "future-invalid");
});

test("planned exam conflict docs ignore non-scheduled and non-overlapping appointments", () => {
  const docs = [
    fakeDoc({
      id: "conflict",
      status: "scheduled",
      scheduledStart: fakeTimestamp(new Date("2099-09-15T10:30:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T10:40:00+03:00")),
    }),
    fakeDoc({
      id: "cancelled",
      status: "cancelled",
      scheduledStart: fakeTimestamp(new Date("2099-09-15T10:30:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T10:40:00+03:00")),
    }),
    fakeDoc({
      id: "outside",
      status: "scheduled",
      scheduledStart: fakeTimestamp(new Date("2099-09-15T13:00:00+03:00")),
      scheduledEnd: fakeTimestamp(new Date("2099-09-15T13:10:00+03:00")),
    }),
  ];

  const conflicts = helpers.plannedExamConflictDocs(
    docs,
    new Date("2099-09-15T10:00:00+03:00"),
    new Date("2099-09-15T12:45:00+03:00"),
    new Date("2099-09-15T09:00:00+03:00")
  );

  assert.equal(conflicts.length, 1);
  assert.equal(conflicts[0].id, "conflict");
});

test("no-show with same-day queue activity becomes verified", async () => {
  const doc = fakeNoShowDoc("no-show-a", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });

  const result = await helpers.reconcileNoShowAppointmentDocs(
    [doc],
    async () => ({ verified: true, reason: "queue_activity" })
  );

  assert.equal(result.verifiedCount, 1);
  assert.equal(doc.updates[0].noShowVerificationStatus, "verified");
  assert.equal(doc.updates[0].noShowVerificationReason, "queue_activity");
});

test("no-show with same-day study activity becomes verified", async () => {
  const doc = fakeNoShowDoc("no-show-study", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });

  await helpers.reconcileNoShowAppointmentDocs(
    [doc],
    async () => ({ verified: true, reason: "study_activity" })
  );

  assert.equal(doc.updates[0].noShowVerificationStatus, "verified");
  assert.equal(doc.updates[0].noShowVerificationReason, "study_activity");
});

test("no-show without same-day activity becomes unverified", async () => {
  const doc = fakeNoShowDoc("no-show-b", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-b",
    dateKey: "2099-09-15",
  });

  const result = await helpers.reconcileNoShowAppointmentDocs(
    [doc],
    async () => ({ verified: false })
  );

  assert.equal(result.unverifiedCount, 1);
  assert.equal(doc.updates[0].noShowVerificationStatus, "unverified");
  assert.equal(doc.updates[0].noShowVerificationReason, null);
});

test("previous-day activity does not verify a no-show", async () => {
  const doc = fakeNoShowDoc("no-show-previous-day", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });

  await helpers.reconcileNoShowAppointmentDocs(
    [doc],
    async (studentId, dateKey) => ({
      verified: dateKey === "2099-09-14",
      reason: "queue_activity",
    })
  );

  assert.equal(doc.updates[0].noShowVerificationStatus, "unverified");
});

test("non-no-show appointment statuses are ignored by reconciliation", async () => {
  const docs = [
    fakeNoShowDoc("cancelled", {
      status: "cancelled",
      noShowVerificationStatus: "pending",
      studentId: "student-a",
      dateKey: "2099-09-15",
    }),
    fakeNoShowDoc("completed", {
      status: "completed",
      noShowVerificationStatus: "pending",
      studentId: "student-a",
      dateKey: "2099-09-15",
    }),
    fakeNoShowDoc("scheduled", {
      status: "scheduled",
      noShowVerificationStatus: "pending",
      studentId: "student-a",
      dateKey: "2099-09-15",
    }),
  ];

  await helpers.reconcileNoShowAppointmentDocs(
    docs,
    async () => ({ verified: true, reason: "queue_activity" })
  );

  assert.equal(docs.every((doc) => doc.updates.length === 0), true);
});

test("duplicate same-student no-shows reuse one activity lookup", async () => {
  const docs = [
    fakeNoShowDoc("no-show-1", {
      status: "no_show",
      noShowVerificationStatus: "pending",
      studentId: "student-a",
      dateKey: "2099-09-15",
    }),
    fakeNoShowDoc("no-show-2", {
      status: "no_show",
      noShowVerificationStatus: "pending",
      studentId: "student-a",
      dateKey: "2099-09-15",
    }),
  ];
  let lookups = 0;

  const result = await helpers.reconcileNoShowAppointmentDocs(
    docs,
    async () => {
      lookups += 1;
      return { verified: true, reason: "queue_activity" };
    }
  );

  assert.equal(lookups, 1);
  assert.equal(result.uniqueStudentLookups, 1);
  assert.equal(result.verifiedCount, 2);
});

test("duplicate same-student no-shows reuse activity lookup across batches", async () => {
  const firstBatchDoc = fakeNoShowDoc("no-show-1", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });
  const secondBatchDoc = fakeNoShowDoc("no-show-2", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });
  const activityCache = new Map();
  let lookups = 0;

  const firstResult = await helpers.reconcileNoShowAppointmentDocs(
    [firstBatchDoc],
    async () => {
      lookups += 1;
      return { verified: true, reason: "queue_activity" };
    },
    activityCache
  );
  const secondResult = await helpers.reconcileNoShowAppointmentDocs(
    [secondBatchDoc],
    async () => {
      lookups += 1;
      return { verified: true, reason: "queue_activity" };
    },
    activityCache
  );

  assert.equal(lookups, 1);
  assert.equal(firstResult.uniqueStudentLookups, 1);
  assert.equal(secondResult.uniqueStudentLookups, 0);
});

test("day-end marker waits until every pending no-show page is processed", () => {
  assert.equal(
    helpers.noShowReconciliationCanWriteMarker(
      { failedCount: 0 },
      1
    ),
    false
  );
  assert.equal(
    helpers.noShowReconciliationCanWriteMarker(
      { failedCount: 1 },
      0
    ),
    false
  );
  assert.equal(
    helpers.noShowReconciliationCanWriteMarker(
      { failedCount: 0 },
      0
    ),
    true
  );
});

test("failed no-show record processing does not stop other records", async () => {
  const failingDoc = fakeNoShowDoc("no-show-fail", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-a",
    dateKey: "2099-09-15",
  });
  failingDoc.ref.update = async () => {
    throw new Error("temporary write failure");
  };
  const okDoc = fakeNoShowDoc("no-show-ok", {
    status: "no_show",
    noShowVerificationStatus: "pending",
    studentId: "student-b",
    dateKey: "2099-09-15",
  });

  const result = await helpers.reconcileNoShowAppointmentDocs(
    [failingDoc, okDoc],
    async () => ({ verified: true, reason: "queue_activity" })
  );

  assert.equal(result.failedCount, 1);
  assert.equal(result.verifiedCount, 1);
  assert.equal(okDoc.updates[0].noShowVerificationStatus, "verified");
});

test("verified warning popup is eligible for 7 days only", () => {
  const now = new Date("2099-09-15T12:00:00+03:00");

  assert.equal(
    helpers.verifiedNoShowPopupEligible(
      new Date("2099-09-08T12:00:00+03:00"),
      now
    ),
    true
  );
  assert.equal(
    helpers.verifiedNoShowPopupEligible(
      new Date("2099-09-08T11:59:00+03:00"),
      now
    ),
    false
  );
});

test("verified notification history is eligible for 14 days only", () => {
  const now = new Date("2099-09-15T12:00:00+03:00");

  assert.equal(
    helpers.verifiedNoShowHistoryEligible(
      new Date("2099-09-01T12:00:00+03:00"),
      now
    ),
    true
  );
  assert.equal(
    helpers.verifiedNoShowHistoryEligible(
      new Date("2099-09-01T11:59:00+03:00"),
      now
    ),
    false
  );
});

test("day-end marker prevents duplicate no-show reconciliation", () => {
  const runTime = new Date("2099-09-15T23:50:00+03:00");

  assert.equal(
    helpers.shouldRunNoShowReconciliation(runTime, "2099-09-14"),
    true
  );
  assert.equal(
    helpers.shouldRunNoShowReconciliation(runTime, "2099-09-15"),
    false
  );
  assert.equal(
    helpers.shouldRunNoShowReconciliation(
      new Date("2099-09-15T23:30:00+03:00"),
      "2099-09-14"
    ),
    false
  );
});
