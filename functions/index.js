const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

const REGION = "us-central1";
const TIME_ZONE = "Europe/Istanbul";
const BULK_DELETE_LIMIT = 500;
const BULK_DELETE_CHUNK_SIZE = 25;
const AUTH_DELETE_RETRY_DELAYS_MS = [750, 1500, 3000];
const APPOINTMENT_STATUS_SCHEDULED = "scheduled";
const APPOINTMENT_STATUS_EXPIRED = "expired";
const ACTIVE_APPOINTMENT_STATUSES = ["scheduled", "started"];
const APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES = 2;
const APPOINTMENT_PLANNED_CAPACITY_RATIO = 0.65;
const APPOINTMENT_OPTION_STEP_MINUTES = 5;
const MAX_AVAILABILITY_TEACHERS = 50;
const NO_SHOW_VERIFICATION_PENDING = "pending";
const NO_SHOW_VERIFICATION_VERIFIED = "verified";
const NO_SHOW_VERIFICATION_UNVERIFIED = "unverified";
const NO_SHOW_RECONCILIATION_START_MINUTE = 23 * 60 + 45;
const NO_SHOW_RECONCILIATION_END_MINUTE = 23 * 60 + 59;
const PLANNED_EXAM_STATUS_SCHEDULED = "scheduled";
const PLANNED_EXAM_STATUS_ACTIVE = "active";
const PLANNED_EXAM_DURATIONS = {
  tyt: 165,
  ayt: 180,
};

// ============================================================
// ORTAK YARDIMCI FONKSİYONLAR
// ============================================================

function getIstanbulDateParts(date = new Date()) {
  const formatter = new Intl.DateTimeFormat("en-GB", {
    timeZone: TIME_ZONE,
    weekday: "short",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });

  const parts = formatter.formatToParts(date);
  const values = {};

  for (const part of parts) {
    if (part.type !== "literal") {
      values[part.type] = part.value;
    }
  }

  return {
    weekday: values.weekday,
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
    hour: Number(values.hour),
    minute: Number(values.minute),
    dateKey: `${values.year}-${values.month}-${values.day}`,
  };
}

function timeToMinutes(value) {
  if (typeof value !== "string") {
    return -1;
  }

  const parts = value.trim().split(":");

  if (parts.length !== 2) {
    return -1;
  }

  const hour = Number(parts[0]);
  const minute = Number(parts[1]);

  if (
    !Number.isInteger(hour) ||
    !Number.isInteger(minute) ||
    hour < 0 ||
    hour > 23 ||
    minute < 0 ||
    minute > 59
  ) {
    return -1;
  }

  return hour * 60 + minute;
}

function isWeekend(weekday) {
  return weekday === "Sat" || weekday === "Sun";
}

function weekdayAvailabilityKey(weekday) {
  const keys = {
    Mon: "monday",
    Tue: "tuesday",
    Wed: "wednesday",
    Thu: "thursday",
    Fri: "friday",
    Sat: "saturday",
    Sun: "sunday",
  };

  return keys[weekday] || "monday";
}

function normalizeScheduleSlots(rawSlots) {
  if (!Array.isArray(rawSlots)) {
    return [];
  }

  return rawSlots
    .map((slot) => ({
      start: String(slot?.start ?? ""),
      end: String(slot?.end ?? ""),
      startMinutes: timeToMinutes(String(slot?.start ?? "")),
      endMinutes: timeToMinutes(String(slot?.end ?? "")),
    }))
    .filter(
      (slot) =>
        slot.startMinutes >= 0 &&
        slot.endMinutes >= 0 &&
        slot.endMinutes > slot.startMinutes
    );
}

function getDailySchedule(scheduleData, weekday) {
  const dayKey = weekdayAvailabilityKey(weekday);
  const weeklySchedule = scheduleData.weeklySchedule || {};
  const daily = weeklySchedule[dayKey];

  if (daily && typeof daily === "object") {
    const legacyClosed = daily.closed === true;
    return {
      closed: legacyClosed,
      zumreClosed: legacyClosed || daily.zumreClosed === true,
      studyClosed: legacyClosed || daily.studyClosed === true,
      zumreSlots: normalizeScheduleSlots(daily.zumreSlots),
      studySlots: normalizeScheduleSlots(daily.studySlots),
    };
  }

  const weekendDay = isWeekend(weekday);
  return {
    closed: false,
    zumreClosed: false,
    studyClosed: false,
    zumreSlots: normalizeScheduleSlots(
      weekendDay ? scheduleData.weekendSlots : scheduleData.weekdaySlots
    ),
    studySlots: normalizeScheduleSlots(
      weekendDay
        ? scheduleData.weekendStudySlots
        : scheduleData.weekdayStudySlots
    ),
  };
}

function getStudySlots(scheduleData, weekday) {
  const daily = getDailySchedule(scheduleData, weekday);
  return daily.studyClosed ? [] : daily.studySlots;
}

function getZumreSlots(scheduleData, weekday) {
  const daily = getDailySchedule(scheduleData, weekday);
  return daily.zumreClosed ? [] : daily.zumreSlots;
}

function weekdayKeyFromDate(date) {
  return weekdayAvailabilityKey(getIstanbulDateParts(date).weekday);
}

function weekdayShortFromKey(key) {
  const map = {
    monday: "Mon",
    tuesday: "Tue",
    wednesday: "Wed",
    thursday: "Thu",
    friday: "Fri",
    saturday: "Sat",
    sunday: "Sun",
  };

  return map[key] || "Mon";
}

function normalizeWeeklySchedule(rawWeekly = {}) {
  const keys = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
  ];
  const result = {};

  for (const key of keys) {
    const day = rawWeekly[key] || {};
    const legacyClosed = day.closed === true;
    result[key] = {
      closed: legacyClosed,
      zumreClosed: legacyClosed || day.zumreClosed === true,
      studyClosed: legacyClosed || day.studyClosed === true,
      zumreSlots: normalizeScheduleSlots(day.zumreSlots),
      studySlots: normalizeScheduleSlots(day.studySlots),
    };
  }

  return result;
}

function scheduleWithWeekly(scheduleData = {}, weeklySchedule = {}) {
  return {
    ...scheduleData,
    weeklySchedule: normalizeWeeklySchedule(weeklySchedule),
  };
}

function slotsSignature(slots) {
  return normalizeScheduleSlots(slots)
    .map((slot) => `${slot.start}-${slot.end}`)
    .join("|");
}

function changedZumreDayKeys(oldScheduleData = {}, newWeeklySchedule = {}) {
  const keys = Object.keys(normalizeWeeklySchedule(newWeeklySchedule));
  const nextSchedule = scheduleWithWeekly(oldScheduleData, newWeeklySchedule);

  return keys.filter((key) => {
    const oldDay = getDailySchedule(oldScheduleData, weekdayShortFromKey(key));
    const newDay = nextSchedule.weeklySchedule[key] || {};
    return oldDay.zumreClosed !== (newDay.zumreClosed === true) ||
      slotsSignature(oldDay.zumreSlots) !== slotsSignature(newDay.zumreSlots);
  });
}

function isNowInSlots(currentMinutes, slots) {
  return slots.some(
    (slot) =>
      currentMinutes >= slot.startMinutes &&
      currentMinutes < slot.endMinutes
  );
}

function getTeacherAvailabilitySlots(teacherData, weekday) {
  const weeklyAvailability = teacherData.weeklyAvailability || {};
  const rawSlots = weeklyAvailability[weekdayAvailabilityKey(weekday)];

  if (!Array.isArray(rawSlots)) {
    return [];
  }

  return rawSlots
    .map((slot) => ({
      start: String(slot?.start ?? ""),
      end: String(slot?.end ?? ""),
      startMinutes: timeToMinutes(String(slot?.start ?? "")),
      endMinutes: timeToMinutes(String(slot?.end ?? "")),
    }))
    .filter(
      (slot) =>
        slot.startMinutes >= 0 &&
        slot.endMinutes >= 0 &&
        slot.endMinutes > slot.startMinutes
    );
}

function isTeacherScheduledNow(teacherData, now = new Date()) {
  const nowParts = getIstanbulDateParts(now);
  const currentMinutes = nowParts.hour * 60 + nowParts.minute;
  const slots = getTeacherAvailabilitySlots(
    teacherData,
    nowParts.weekday
  );

  return isNowInSlots(currentMinutes, slots);
}

function isManualAbsentToday(teacherData, now = new Date()) {
  return teacherData.manualAbsentDate === getIstanbulDateParts(now).dateKey;
}

function timestampToDate(value) {
  if (value && typeof value.toDate === "function") {
    return value.toDate();
  }

  return null;
}

function resolveTeacherLifecycleStatus(
  teacherData,
  now = new Date(),
  options = {}
) {
  if (isManualAbsentToday(teacherData, now)) {
    return {
      status: "absent",
      clearBreakUntil: true,
    };
  }

  const breakUntilDate = timestampToDate(teacherData.breakUntil);
  if (!options.ignoreBreak && breakUntilDate && breakUntilDate > now) {
    return {
      status: "break",
      clearBreakUntil: false,
    };
  }

  return {
    status: isTeacherScheduledNow(teacherData, now)
      ? "available"
      : "absent",
    clearBreakUntil: Boolean(breakUntilDate),
  };
}

async function syncTeacherStatuses(now = new Date()) {
  const snapshot = await db
    .collection("users")
    .where("role", "==", "teacher")
    .get();

  if (snapshot.empty) {
    return {
      checkedCount: 0,
      updatedCount: 0,
    };
  }

  let batch = db.batch();
  let batchSize = 0;
  let updatedCount = 0;
  const todayKey = getIstanbulDateParts(now).dateKey;

  for (const teacherDoc of snapshot.docs) {
    const teacherData = teacherDoc.data();
    const currentStatus = teacherData.teacherStatus || "absent";

    if (currentStatus === "studyGuard") {
      continue;
    }

    const resolved = resolveTeacherLifecycleStatus(teacherData, now);
    const updateData = {};

    if (currentStatus !== resolved.status) {
      updateData.teacherStatus = resolved.status;
    }

    if (resolved.clearBreakUntil && teacherData.breakUntil) {
      updateData.breakUntil = fieldValue.delete();
    }

    if (
      resolved.status === "available" &&
      teacherData.manualAbsentDate &&
      teacherData.manualAbsentDate !== todayKey
    ) {
      updateData.manualAbsentDate = fieldValue.delete();
    }

    if (Object.keys(updateData).length === 0) {
      continue;
    }

    batch.update(teacherDoc.ref, {
      ...updateData,
      updatedAt: fieldValue.serverTimestamp(),
    });
    batchSize += 1;
    updatedCount += 1;

    if (batchSize >= 400) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  return {
    checkedCount: snapshot.size,
    updatedCount,
  };
}

function buildRuntimeScheduleState(scheduleData, now = new Date()) {
  const nowParts = getIstanbulDateParts(now);
  const currentMinutes = nowParts.hour * 60 + nowParts.minute;
  const dailySchedule = getDailySchedule(scheduleData, nowParts.weekday);
  const zumreSlots = dailySchedule.zumreClosed ? [] : dailySchedule.zumreSlots;
  const studySlots = dailySchedule.studyClosed ? [] : dailySchedule.studySlots;
  const isZumreOpen = isNowInSlots(currentMinutes, zumreSlots);
  const isStudyOpen = isNowInSlots(currentMinutes, studySlots);

  return {
    isZumreOpen,
    isLunchBreak: false,
    isStudyOpen,
    currentPeriod: isStudyOpen
        ? "study"
        : isZumreOpen
          ? "zumre"
          : "closed",
    dailyClosed: dailySchedule.closed,
    zumreClosed: dailySchedule.zumreClosed,
    studyClosed: dailySchedule.studyClosed,
  };
}

function resolveInstitutionMode(runtimeData = {}, now = new Date()) {
  const nowParts = getIstanbulDateParts(now);
  const mode = runtimeData.institutionMode || "active";

  if (mode === "closed" && runtimeData.closedDate === nowParts.dateKey) {
    return {
      institutionMode: "closed",
      closedDate: runtimeData.closedDate,
      examType: null,
      examEndsAt: null,
    };
  }

  if (mode === "exam") {
    const examEndsAt = timestampToDate(runtimeData.examEndsAt);
    if (examEndsAt && examEndsAt > now) {
      return {
        institutionMode: "exam",
        closedDate: null,
        examType: runtimeData.examType || null,
        examEndsAt: runtimeData.examEndsAt,
      };
    }
  }

  return {
    institutionMode: "active",
    closedDate: null,
    examType: null,
    examEndsAt: null,
  };
}

function buildEffectiveRuntimeState(
  scheduleData,
  runtimeData = {},
  now = new Date()
) {
  const scheduleState = buildRuntimeScheduleState(scheduleData, now);
  const institutionState = resolveInstitutionMode(runtimeData, now);

  if (institutionState.institutionMode === "active") {
    return {
      ...scheduleState,
      ...institutionState,
    };
  }

  return {
    ...scheduleState,
    isZumreOpen: false,
    isStudyOpen: false,
    isLunchBreak: false,
    currentPeriod: institutionState.institutionMode,
    ...institutionState,
  };
}

/*
 * Bir etüt oturumunun hangi yönetici tanımlı saat aralığına
 * ait olduğunu başlangıç zamanından bulur.
 */
function findSessionSlot(sessionStartedAt, scheduleData) {
  if (!sessionStartedAt || typeof sessionStartedAt.toDate !== "function") {
    return null;
  }

  const startedDate = sessionStartedAt.toDate();
  const startedParts = getIstanbulDateParts(startedDate);
  const startedMinutes = startedParts.hour * 60 + startedParts.minute;

  const slots = getStudySlots(scheduleData, startedParts.weekday);

  const matchingSlot = slots.find(
    (slot) =>
      startedMinutes >= slot.startMinutes &&
      startedMinutes < slot.endMinutes
  );

  if (!matchingSlot) {
    return null;
  }

  return {
    ...matchingSlot,
    dateKey: startedParts.dateKey,
  };
}

/*
 * Başlangıç dahil, bitiş hariç:
 *
 * 20:00 <= şimdi < 20:30  → aktif
 * şimdi >= 20:30          → kapanmalı
 */
function shouldCloseSession(sessionData, scheduleData, now = new Date()) {
  const slot = findSessionSlot(sessionData.startedAt, scheduleData);

  /*
   * Oturum hiçbir tanımlı saate bağlanamıyorsa güvenli tarafta
   * kalıp süresi geçmiş/eski bir oturum olarak kapatıyoruz.
   */
  if (!slot) {
    return true;
  }

  const nowParts = getIstanbulDateParts(now);

  if (nowParts.dateKey !== slot.dateKey) {
    return true;
  }

  const currentMinutes = nowParts.hour * 60 + nowParts.minute;

  return currentMinutes >= slot.endMinutes;
}

function findCurrentStudySlot(scheduleData, now = new Date()) {
  const nowParts = getIstanbulDateParts(now);
  const currentMinutes = nowParts.hour * 60 + nowParts.minute;
  const slots = getStudySlots(scheduleData, nowParts.weekday);
  const slot = slots.find(
    (item) =>
      currentMinutes >= item.startMinutes &&
      currentMinutes < item.endMinutes
  );

  if (!slot) {
    return null;
  }

  return {
    ...slot,
    dateKey: nowParts.dateKey,
  };
}

function studySessionIdFor(staffId, slot) {
  const safeStart = slot.start.replace(/:/g, "");
  const safeEnd = slot.end.replace(/:/g, "");
  return `${staffId}_${slot.dateKey}-${safeStart}-${safeEnd}`;
}

function findZumreSlot(startedAt, scheduleData) {
  if (!startedAt || typeof startedAt.toDate !== "function") {
    return null;
  }

  const startedDate = startedAt.toDate();
  const startedParts = getIstanbulDateParts(startedDate);
  const startedMinutes = startedParts.hour * 60 + startedParts.minute;
  const slots = getZumreSlots(scheduleData, startedParts.weekday);

  const matchingSlot = slots.find(
    (slot) =>
      startedMinutes >= slot.startMinutes &&
      startedMinutes < slot.endMinutes
  );

  if (!matchingSlot) {
    return null;
  }

  return {
    ...matchingSlot,
    dateKey: startedParts.dateKey,
  };
}

function shouldAutoCompleteZumreQueue(queueData, scheduleData, now = new Date()) {
  const nowParts = getIstanbulDateParts(now);
  const currentMinutes = nowParts.hour * 60 + nowParts.minute;
  const currentZumreSlots = getZumreSlots(scheduleData, nowParts.weekday);

  if (isNowInSlots(currentMinutes, currentZumreSlots)) {
    return false;
  }

  const queueSlot = findZumreSlot(queueData.startedAt, scheduleData);

  if (!queueSlot) {
    return false;
  }

  if (nowParts.dateKey !== queueSlot.dateKey) {
    return true;
  }

  return currentMinutes >= queueSlot.endMinutes + 15;
}

async function completeTimedOutZumreQueues(scheduleData, now = new Date()) {
  const snapshot = await db
    .collection("queues")
    .where("status", "==", "in_progress")
    .get();

  if (snapshot.empty) {
    return {
      checkedCount: 0,
      completedCount: 0,
    };
  }

  const batch = db.batch();
  let checkedCount = 0;
  let completedCount = 0;

  for (const queueDoc of snapshot.docs) {
    checkedCount += 1;
    const queueData = queueDoc.data();

    if (!shouldAutoCompleteZumreQueue(queueData, scheduleData, now)) {
      continue;
    }

    batch.update(queueDoc.ref, {
      status: "completed",
      completedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
      autoCompleted: true,
      autoCompleteReason: "zumre_timeout",
    });
    completedCount += 1;
  }

  if (completedCount > 0) {
    await batch.commit();
  }

  return {
    checkedCount,
    completedCount,
  };
}

async function deleteWaitingZumreQueuesWhenClosed(
  scheduleData,
  now = new Date(),
  options = {}
) {
  const nowParts = getIstanbulDateParts(now);
  const currentMinutes = nowParts.hour * 60 + nowParts.minute;
  const currentZumreSlots = getZumreSlots(scheduleData, nowParts.weekday);

  if (!options.forceClosed && isNowInSlots(currentMinutes, currentZumreSlots)) {
    return {
      checkedCount: 0,
      deletedCount: 0,
      skippedBecauseOpen: true,
    };
  }

  const snapshot = await db
    .collection("queues")
    .where("status", "==", "waiting")
    .get();

  if (snapshot.empty) {
    return {
      checkedCount: 0,
      deletedCount: 0,
      skippedBecauseOpen: false,
    };
  }

  let batch = db.batch();
  let batchSize = 0;
  let deletedCount = 0;

  for (const queueDoc of snapshot.docs) {
    batch.delete(queueDoc.ref);
    batchSize += 1;
    deletedCount += 1;

    if (batchSize >= 400) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  return {
    checkedCount: snapshot.size,
    deletedCount,
    skippedBecauseOpen: false,
  };
}

// ============================================================
// KULLANICI ŞİFRESİ GÜNCELLEME
// ============================================================

const USER_ROLES = ["admin", "teacher", "student", "studyGuard"];
const USER_EMAIL_DOMAIN = "@bilimkalesi.com";

async function assertAdminCaller(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Giriş yapılmamış."
    );
  }

  const adminDoc = await db
    .collection("users")
    .doc(request.auth.uid)
    .get();

  if (!adminDoc.exists || adminDoc.data()?.role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Bu işlem için yetkiniz yok."
    );
  }

  return request.auth.uid;
}

function normalizeUsername(value) {
  return String(value || "")
    .trim()
    .replace(/\s+/g, "")
    .toLowerCase();
}

function emailFromUsername(username) {
  return `${normalizeUsername(username)}${USER_EMAIL_DOMAIN}`;
}

function cleanText(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function cleanSubjects(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map((item) => cleanText(item))
    .filter((item, index, list) => item && list.indexOf(item) === index);
}

function normalizeSubjectText(value) {
  return cleanText(value)
    .toLocaleLowerCase("tr-TR")
    .replace(/ı/g, "i")
    .replace(/ş/g, "s")
    .replace(/ğ/g, "g")
    .replace(/ü/g, "u")
    .replace(/ö/g, "o")
    .replace(/ç/g, "c");
}

function teacherSubjects(teacherData = {}) {
  const subjects = [];
  const rawSubjects = teacherData.subjects;

  if (Array.isArray(rawSubjects)) {
    subjects.push(...rawSubjects);
  } else if (typeof rawSubjects === "string") {
    subjects.push(...rawSubjects.split(/[,;/|]/));
  }

  if (teacherData.branch) {
    subjects.push(teacherData.branch);
  }

  if (teacherData.subject) {
    subjects.push(teacherData.subject);
  }

  return subjects
    .map((item) => cleanText(item))
    .filter((item) => item);
}

function teacherHasSubject(teacherData, subject) {
  const normalizedSubject = normalizeSubjectText(subject);
  return teacherSubjects(teacherData).some(
    (teacherSubject) => normalizeSubjectText(teacherSubject) === normalizedSubject
  );
}

function normalizeQuestionCount(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 1;
  }

  return Math.min(Math.max(Math.trunc(parsed), 1), 4);
}

function estimatedMinutesForQuestionCount(questionCount) {
  if (questionCount === 1) return 4;
  if (questionCount === 2) return 7;
  if (questionCount === 3) return 10;
  return 13;
}

function dateKeyFromIstanbulDate(date) {
  return getIstanbulDateParts(date).dateKey;
}

function istanbulDayBoundsFromDateKey(dateKey) {
  if (typeof dateKey !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
    return null;
  }

  const start = new Date(`${dateKey}T00:00:00+03:00`);
  if (Number.isNaN(start.getTime())) return null;

  return {
    start,
    end: new Date(start.getTime() + 24 * 60 * 60 * 1000),
  };
}

function shouldRunNoShowReconciliation(now, lastDateKey) {
  const parts = getIstanbulDateParts(now);
  const minuteOfDay = parts.hour * 60 + parts.minute;

  return (
    minuteOfDay >= NO_SHOW_RECONCILIATION_START_MINUTE &&
    minuteOfDay <= NO_SHOW_RECONCILIATION_END_MINUTE &&
    lastDateKey !== parts.dateKey
  );
}

function noShowVerificationUpdate(activity) {
  if (activity?.verified) {
    return {
      noShowVerificationStatus: NO_SHOW_VERIFICATION_VERIFIED,
      noShowVerifiedAt: fieldValue.serverTimestamp(),
      noShowVerificationReason: activity.reason,
      noShowVerificationCheckedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    };
  }

  return {
    noShowVerificationStatus: NO_SHOW_VERIFICATION_UNVERIFIED,
    noShowVerifiedAt: null,
    noShowVerificationReason: null,
    noShowVerificationCheckedAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
  };
}

function verifiedNoShowPopupEligible(verifiedAt, now = new Date()) {
  const verifiedDate = timestampToDate(verifiedAt) || verifiedAt;
  if (!(verifiedDate instanceof Date) || Number.isNaN(verifiedDate.getTime())) {
    return false;
  }

  const ageMs = now.getTime() - verifiedDate.getTime();
  return ageMs >= 0 && ageMs <= 7 * 24 * 60 * 60 * 1000;
}

function verifiedNoShowHistoryEligible(verifiedAt, now = new Date()) {
  const verifiedDate = timestampToDate(verifiedAt) || verifiedAt;
  if (!(verifiedDate instanceof Date) || Number.isNaN(verifiedDate.getTime())) {
    return false;
  }

  const ageMs = now.getTime() - verifiedDate.getTime();
  return ageMs >= 0 && ageMs <= 14 * 24 * 60 * 60 * 1000;
}

function parseRequestedAppointmentStart(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (typeof value === "string" && value.trim()) {
    const date = new Date(value.trim());
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (value && typeof value.toDate === "function") {
    const date = value.toDate();
    return Number.isNaN(date.getTime()) ? null : date;
  }

  return null;
}

function parseRequestedPlannedExamStart(data = {}) {
  const dateKey = cleanText(data.dateKey);
  const startTime = cleanText(data.startTime);

  if (/^\d{4}-\d{2}-\d{2}$/.test(dateKey) && /^\d{2}:\d{2}$/.test(startTime)) {
    const minutes = timeToMinutes(startTime);
    if (minutes >= 0) {
      const date = new Date(`${dateKey}T${startTime}:00+03:00`);
      return Number.isNaN(date.getTime()) ? null : date;
    }
  }

  return parseRequestedAppointmentStart(data.scheduledStart);
}

function parseDateKeyToIstanbulNoon(dateKey) {
  if (typeof dateKey !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(dateKey)) {
    return null;
  }

  const date = new Date(`${dateKey}T12:00:00+03:00`);
  return Number.isNaN(date.getTime()) ? null : date;
}

function timestampFromDate(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

function cleanIdempotencyKey(value) {
  const key = cleanText(value);
  if (!key || key.length > 80) {
    return "";
  }

  return key.replace(/[^A-Za-z0-9._-]/g, "_");
}

function appointmentIdFor(studentId, idempotencyKey) {
  const hash = crypto
    .createHash("sha256")
    .update(`${studentId}:${idempotencyKey}`)
    .digest("hex")
    .slice(0, 32);

  return `${studentId}_${hash}`;
}

function appointmentLockId(scope, id, dateKey) {
  const hash = crypto
    .createHash("sha256")
    .update(`${scope}:${id}:${dateKey}`)
    .digest("hex")
    .slice(0, 32);

  return `${scope}_${hash}`;
}

function intervalsOverlap(firstStart, firstEnd, secondStart, secondEnd) {
  return firstStart < secondEnd && secondStart < firstEnd;
}

function appointmentIntervalMinutes(appointmentData) {
  const start = timestampToDate(appointmentData.scheduledStart);
  const end = timestampToDate(appointmentData.scheduledEnd);

  if (!start || !end) {
    return null;
  }

  return {
    start,
    end,
    startMs: start.getTime(),
    endMs: end.getTime(),
  };
}

function appointmentStatusIsActive(data) {
  return !data.status || ACTIVE_APPOINTMENT_STATUSES.includes(data.status);
}

function plannedExamDurationMinutes(type) {
  return PLANNED_EXAM_DURATIONS[cleanText(type).toLowerCase()] || 0;
}

function plannedExamItemFromRaw(raw, fallbackId = "legacy") {
  if (!raw || typeof raw !== "object") return null;

  const status = cleanText(raw.status);
  if (
    status !== PLANNED_EXAM_STATUS_SCHEDULED &&
    status !== PLANNED_EXAM_STATUS_ACTIVE
  ) {
    return null;
  }

  const start = timestampToDate(raw.scheduledStart);
  const end = timestampToDate(raw.scheduledEnd);
  const examType = cleanText(raw.examType).toLowerCase();
  if (!start || !end || end <= start || !plannedExamDurationMinutes(examType)) {
    return null;
  }

  return {
    id: cleanText(raw.id) || fallbackId,
    status,
    examType,
    scheduledStart: raw.scheduledStart,
    scheduledEnd: raw.scheduledEnd,
    start,
    end,
  };
}

function plannedExamItems(plannedExamData = {}) {
  const items = [];
  const rawItems = Array.isArray(plannedExamData.items)
    ? plannedExamData.items
    : [];

  rawItems.forEach((item, index) => {
    const parsed = plannedExamItemFromRaw(item, `exam_${index}`);
    if (parsed) items.push(parsed);
  });

  if (items.length === 0) {
    const legacy = plannedExamItemFromRaw(plannedExamData);
    if (legacy) items.push(legacy);
  }

  return items.sort((a, b) => a.start.getTime() - b.start.getTime());
}

function publicPlannedExamItem(item) {
  return {
    id: item.id,
    status: item.status,
    examType: item.examType,
    scheduledStart: item.scheduledStart,
    scheduledEnd: item.scheduledEnd,
  };
}

function plannedExamPrimaryFields(items) {
  const active = items.find((item) => item.status === PLANNED_EXAM_STATUS_ACTIVE);
  const scheduled = items.find(
    (item) => item.status === PLANNED_EXAM_STATUS_SCHEDULED
  );
  const primary = active || scheduled;

  if (!primary) {
    return {
      status: "idle",
      examType: null,
      scheduledStart: null,
      scheduledEnd: null,
    };
  }

  return {
    status: primary.status,
    examType: primary.examType,
    scheduledStart: primary.scheduledStart,
    scheduledEnd: primary.scheduledEnd,
  };
}

function plannedExamItemsAfterCompletingActive(plannedExamData = {}) {
  const items = plannedExamItems(plannedExamData);
  const nextItems = [];
  let completedCount = 0;

  for (const item of items) {
    if (item.status === PLANNED_EXAM_STATUS_ACTIVE) {
      completedCount += 1;
      continue;
    }

    nextItems.push(publicPlannedExamItem(item));
  }

  return {
    completedCount,
    nextItems,
  };
}

async function completeActivePlannedExams(now = new Date(), adminUid = null) {
  const plannedExamRef = db.collection("settings").doc("plannedExam");
  const plannedExamDoc = await plannedExamRef.get();

  if (!plannedExamDoc.exists) {
    return { completedCount: 0 };
  }

  const { completedCount, nextItems } =
    plannedExamItemsAfterCompletingActive(plannedExamDoc.data() || {});

  if (completedCount === 0) {
    return { completedCount: 0 };
  }

  await plannedExamRef.set({
    ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
    items: nextItems,
    completedAt: fieldValue.serverTimestamp(),
    manuallyEndedAt: fieldValue.serverTimestamp(),
    completedBy: adminUid,
    updatedAt: fieldValue.serverTimestamp(),
  }, { merge: true });

  return { completedCount };
}

function activePlannedExamWindow(plannedExamData = {}) {
  const item = plannedExamItems(plannedExamData)[0];
  return item ? { start: item.start, end: item.end } : null;
}

function plannedExamConflictsWithAppointment(
  plannedExamData,
  startDate,
  endDate
) {
  return plannedExamItems(plannedExamData).some((item) =>
    intervalsOverlap(
      startDate.getTime(),
      endDate.getTime(),
      item.start.getTime(),
      item.end.getTime()
    )
  );
}

function publicDisplayName(userData, fallback) {
  return (
    userData.fullName ||
    userData.name ||
    userData.username ||
    fallback
  );
}

function findContainingZumreSlot(scheduleData, startDate, endDate) {
  const parts = getIstanbulDateParts(startDate);
  const startMinutes = parts.hour * 60 + parts.minute;
  const durationMinutes = Math.ceil(
    (endDate.getTime() - startDate.getTime()) / 60000
  );
  const endMinutes = startMinutes + durationMinutes;
  const slots = getZumreSlots(scheduleData, parts.weekday);

  return slots.find(
    (slot) =>
      startMinutes >= slot.startMinutes &&
      endMinutes <= slot.endMinutes
  ) || null;
}

function appointmentFitsZumreSchedule(scheduleData, startDate, endDate) {
  return findContainingZumreSlot(scheduleData, startDate, endDate) !== null;
}

function buildSlotKey(dateKey, slot) {
  return `${dateKey}-${slot.start}-${slot.end}`;
}

function teacherScheduledForAppointment(teacherData, startDate, endDate) {
  const parts = getIstanbulDateParts(startDate);
  const startMinutes = parts.hour * 60 + parts.minute;
  const durationMinutes = Math.ceil(
    (endDate.getTime() - startDate.getTime()) / 60000
  );
  const endMinutes = startMinutes + durationMinutes;
  const slots = getTeacherAvailabilitySlots(teacherData, parts.weekday);

  return slots.some(
    (slot) =>
      startMinutes >= slot.startMinutes &&
      endMinutes <= slot.endMinutes
  );
}

function appointmentOverlapsDocs(docs, startDate, endDate, options = {}) {
  const startMs = startDate.getTime();
  const endMs = endDate.getTime();
  const bufferMs = (options.bufferMinutes || 0) * 60 * 1000;

  return docs.some((doc) => {
    const data = doc.data();
    if (!appointmentStatusIsActive(data)) return false;

    const interval = appointmentIntervalMinutes(data);
    if (!interval) return false;

    return intervalsOverlap(
      startMs - bufferMs,
      endMs + bufferMs,
      interval.startMs,
      interval.endMs
    );
  });
}

function appointmentMinutesInSlot(docs, slotKey) {
  return docs.reduce((total, doc) => {
    const data = doc.data();
    if (!appointmentStatusIsActive(data)) return total;
    if (data.slotKey !== slotKey) return total;

    const estimated = Number(data.estimatedMinutes);
    return total + (Number.isFinite(estimated) ? estimated : 0);
  }, 0);
}

function plannedCapacityMinutesForSlot(slot) {
  return Math.floor(
    (slot.endMinutes - slot.startMinutes) * APPOINTMENT_PLANNED_CAPACITY_RATIO
  );
}

function appointmentMatchesBookingIdentity(data, requestData) {
  const existingStart = timestampToDate(data.scheduledStart);
  const requestedStart = requestData.scheduledStart;

  return (
    data.studentId === requestData.studentId &&
    data.teacherId === requestData.teacherId &&
    data.subject === requestData.subject &&
    Number(data.questionCount) === requestData.questionCount &&
    data.dateKey === requestData.dateKey &&
    existingStart &&
    requestedStart &&
    existingStart.getTime() === requestedStart.getTime()
  );
}

function appointmentCanBecomeLive(appointmentData, now = new Date()) {
  if (!appointmentData || appointmentData.status !== APPOINTMENT_STATUS_SCHEDULED) {
    return {
      ok: false,
      reason: "Bu planlı zümre artık başlatılabilir durumda değil.",
    };
  }

  const scheduledStart = timestampToDate(appointmentData.scheduledStart);
  const scheduledEnd = timestampToDate(appointmentData.scheduledEnd);

  if (!scheduledStart || !scheduledEnd) {
    return {
      ok: false,
      reason: "Planlı zümre saat bilgisi geçersiz.",
    };
  }

  if (scheduledStart.getTime() > now.getTime()) {
    return {
      ok: false,
      reason: "Planlı zümre saati henüz gelmedi.",
    };
  }

  if (scheduledEnd.getTime() <= now.getTime()) {
    return {
      ok: false,
      reason: "Planlı zümre zamanı geçti.",
    };
  }

  return { ok: true };
}

function appointmentShouldExpireScheduled(appointmentData, now = new Date()) {
  if (!appointmentData || appointmentData.status !== APPOINTMENT_STATUS_SCHEDULED) {
    return false;
  }

  const scheduledEnd = timestampToDate(appointmentData.scheduledEnd);
  return !!scheduledEnd && scheduledEnd.getTime() <= now.getTime();
}

function expiredAppointmentUpdate() {
  return {
    status: APPOINTMENT_STATUS_EXPIRED,
    expiredAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
  };
}

function appointmentLinkedQueueId(appointmentId) {
  return `appointment_${appointmentId}`;
}

function buildAppointmentLinkedQueueData(appointmentId, appointmentData, now) {
  return {
    studentId: appointmentData.studentId,
    studentName: cleanText(appointmentData.studentName) || "Öğrenci",
    teacherId: appointmentData.teacherId,
    teacherName: cleanText(appointmentData.teacherName) || "Öğretmen",
    subject: cleanText(appointmentData.subject) || "Ders",
    questionCount: normalizeQuestionCount(appointmentData.questionCount),
    estimatedMinutes: Number(appointmentData.estimatedMinutes) ||
      estimatedMinutesForQuestionCount(
        normalizeQuestionCount(appointmentData.questionCount)
      ),
    extraMinutes: 0,
    status: "in_progress",
    source: "appointment",
    appointmentId,
    isManual: false,
    createdAt: fieldValue.serverTimestamp(),
    startedAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
    appointmentScheduledStart: appointmentData.scheduledStart,
    appointmentScheduledEnd: appointmentData.scheduledEnd,
    appointmentStartedAtLocalCheck: now.toISOString(),
  };
}

function appointmentIsFutureScheduled(appointmentData, now = new Date()) {
  if (!appointmentData || appointmentData.status !== APPOINTMENT_STATUS_SCHEDULED) {
    return {
      ok: false,
      reason: "Bu planlı zümre artık düzenlenebilir durumda değil.",
    };
  }

  const scheduledStart = timestampToDate(appointmentData.scheduledStart);
  const scheduledEnd = timestampToDate(appointmentData.scheduledEnd);

  if (!scheduledStart || !scheduledEnd) {
    return {
      ok: false,
      reason: "Planlı zümre saat bilgisi geçersiz.",
    };
  }

  if (scheduledStart.getTime() <= now.getTime()) {
    return {
      ok: false,
      reason: "Başlama zamanı gelen planlı zümre artık düzenlenemez.",
    };
  }

  return {
    ok: true,
    scheduledStart,
    scheduledEnd,
  };
}

function activeAppointmentDocsForTeacher(docs, teacherId, excludeAppointmentId) {
  return docs.filter((doc) => {
    if (doc.id === excludeAppointmentId) return false;
    const data = doc.data();
    return data.teacherId === teacherId && appointmentStatusIsActive(data);
  });
}

function appointmentTransferEligibility({
  appointmentId,
  appointmentData,
  destinationTeacherDoc,
  dateAppointmentDocs,
  studyDutyDocs,
  scheduleData,
  runtimeData,
  plannedExamData,
}) {
  if (!destinationTeacherDoc || !destinationTeacherDoc.exists) {
    return { ok: false, reason: "Seçilen öğretmen bulunamadı." };
  }

  const teacherData = destinationTeacherDoc.data() || {};
  const teacherId = destinationTeacherDoc.id;
  const subject = cleanText(appointmentData.subject);
  const dateKey = cleanText(appointmentData.dateKey);
  const scheduledStart = timestampToDate(appointmentData.scheduledStart);
  const scheduledEnd = timestampToDate(appointmentData.scheduledEnd);

  if (!scheduledStart || !scheduledEnd) {
    return { ok: false, reason: "Planlı zümre saat bilgisi geçersiz." };
  }

  if (teacherData.role !== "teacher") {
    return { ok: false, reason: "Seçilen kullanıcı öğretmen değil." };
  }

  if (!teacherHasSubject(teacherData, subject)) {
    return { ok: false, reason: "Seçilen öğretmen bu ders için uygun değil." };
  }

  if (teacherData.manualAbsentDate === dateKey) {
    return { ok: false, reason: "Seçilen öğretmen o gün kurumda değil görünüyor." };
  }

  const slot = findContainingZumreSlot(scheduleData, scheduledStart, scheduledEnd);
  if (!slot) {
    return { ok: false, reason: "Seçilen saat tanımlı zümre saatleri içinde değil." };
  }

  if (!teacherScheduledForAppointment(teacherData, scheduledStart, scheduledEnd)) {
    return { ok: false, reason: "Seçilen öğretmen bu saatte kurum programında uygun değil." };
  }

  const runtimeConflict = blockingReasonForAppointment({
    runtimeData,
    plannedExamData,
    startDate: scheduledStart,
    endDate: scheduledEnd,
  });
  if (runtimeConflict) {
    return { ok: false, reason: runtimeConflict };
  }

  const teacherDutyDocs = studyDutyDocs.filter(
    (doc) => doc.data().dutyTeacherId === teacherId
  );
  if (studyDutyConflictsWithAppointment(teacherDutyDocs, scheduledStart, scheduledEnd)) {
    return { ok: false, reason: "Seçilen öğretmenin bu saatte etüt görevi bulunuyor." };
  }

  const teacherAppointmentDocs = activeAppointmentDocsForTeacher(
    dateAppointmentDocs,
    teacherId,
    appointmentId
  );

  if (appointmentOverlapsDocs(teacherAppointmentDocs, scheduledStart, scheduledEnd)) {
    return { ok: false, reason: "Seçilen öğretmenin bu saatte başka planlı zümresi var." };
  }

  const slotKey = buildSlotKey(dateKey, slot);
  const usedCapacity = appointmentMinutesInSlot(teacherAppointmentDocs, slotKey);
  const estimatedMinutes = Number(appointmentData.estimatedMinutes) ||
    estimatedMinutesForQuestionCount(
      normalizeQuestionCount(appointmentData.questionCount)
    );

  if (usedCapacity + estimatedMinutes > plannedCapacityMinutesForSlot(slot)) {
    return { ok: false, reason: "Seçilen öğretmenin planlı zümre kapasitesi dolu." };
  }

  return {
    ok: true,
    plannedLoad: usedCapacity,
    teacherName: publicDisplayName(teacherData, "Öğretmen"),
  };
}

function transferEditUntilFor(appointmentData, now = new Date()) {
  const scheduledStart = timestampToDate(appointmentData.scheduledStart);
  const fifteenMinutesLater = new Date(now.getTime() + 15 * 60 * 1000);

  if (!scheduledStart || scheduledStart <= now) {
    return now;
  }

  return scheduledStart < fifteenMinutesLater
    ? scheduledStart
    : fifteenMinutesLater;
}

function canRequesterTransferAppointment(appointmentData, requester, now = new Date()) {
  if (appointmentData.teacherId === requester.uid) {
    return true;
  }

  const editUntil = timestampToDate(appointmentData.transferEditUntil);
  return appointmentData.transferredFromTeacherId === requester.uid &&
    editUntil &&
    editUntil.getTime() > now.getTime() &&
    timestampToDate(appointmentData.scheduledStart)?.getTime() > now.getTime();
}

function institutionConflictsWithAppointment(runtimeData, startDate, endDate) {
  const institutionState = resolveInstitutionMode(runtimeData, new Date());

  if (institutionState.institutionMode === "closed") {
    const appointmentDateKey = dateKeyFromIstanbulDate(startDate);
    if (institutionState.closedDate === appointmentDateKey) {
      return "Kurum seçilen gün kapalı.";
    }
  }

  if (runtimeData?.institutionMode === "exam") {
    const examEndsAt = timestampToDate(runtimeData.examEndsAt);
    const examStartedAt = timestampToDate(runtimeData.examStartedAt) || new Date();
    if (
      examEndsAt &&
      intervalsOverlap(
        startDate.getTime(),
        endDate.getTime(),
        examStartedAt.getTime(),
        examEndsAt.getTime()
      )
    ) {
      return "Seçilen saat deneme modu ile çakışıyor.";
    }
  }

  return null;
}

function blockingReasonForAppointment({
  runtimeData,
  plannedExamData,
  startDate,
  endDate,
}) {
  const runtimeConflict = institutionConflictsWithAppointment(
    runtimeData,
    startDate,
    endDate
  );
  if (runtimeConflict) return runtimeConflict;

  if (plannedExamConflictsWithAppointment(plannedExamData, startDate, endDate)) {
    return "Seçilen saat planlı deneme ile çakışıyor.";
  }

  return null;
}

function summarizeAppointmentConflicts(docs) {
  const grouped = new Map();

  for (const doc of docs) {
    const data = doc.data();
    const start = timestampToDate(data.scheduledStart);
    const end = timestampToDate(data.scheduledEnd);
    if (!start || !end) continue;

    const parts = getIstanbulDateParts(start);
    const weekdayKey = weekdayAvailabilityKey(parts.weekday);
    const key = `${data.dateKey || parts.dateKey}|${weekdayKey}|${parts.hour}:${parts.minute}`;
    const item = grouped.get(key) || {
      dateKey: data.dateKey || parts.dateKey,
      weekday: weekdayKey,
      start: `${String(parts.hour).padStart(2, "0")}:${String(parts.minute).padStart(2, "0")}`,
      end: `${String(getIstanbulDateParts(end).hour).padStart(2, "0")}:${String(getIstanbulDateParts(end).minute).padStart(2, "0")}`,
      count: 0,
    };
    item.count += 1;
    grouped.set(key, item);
  }

  return Array.from(grouped.values()).sort((a, b) =>
    `${a.dateKey} ${a.start}`.localeCompare(`${b.dateKey} ${b.start}`)
  );
}

function scheduleConflictDocsForChange({
  appointmentDocs,
  oldScheduleData,
  newWeeklySchedule,
  now = new Date(),
}) {
  const changedDays = new Set(
    changedZumreDayKeys(oldScheduleData, newWeeklySchedule)
  );
  if (changedDays.size === 0) {
    return [];
  }

  const nextSchedule = scheduleWithWeekly(oldScheduleData, newWeeklySchedule);

  return appointmentDocs.filter((doc) => {
    const data = doc.data();
    if (data.status !== APPOINTMENT_STATUS_SCHEDULED) return false;

    const start = timestampToDate(data.scheduledStart);
    const end = timestampToDate(data.scheduledEnd);
    if (!start || !end || start.getTime() <= now.getTime()) return false;

    if (!changedDays.has(weekdayKeyFromDate(start))) return false;
    return !appointmentFitsZumreSchedule(nextSchedule, start, end);
  });
}

function plannedExamConflictDocs(appointmentDocs, examStart, examEnd, now = new Date()) {
  return appointmentDocs.filter((doc) => {
    const data = doc.data();
    if (data.status !== APPOINTMENT_STATUS_SCHEDULED) return false;

    const start = timestampToDate(data.scheduledStart);
    const end = timestampToDate(data.scheduledEnd);
    if (!start || !end || start.getTime() <= now.getTime()) return false;

    return intervalsOverlap(
      start.getTime(),
      end.getTime(),
      examStart.getTime(),
      examEnd.getTime()
    );
  });
}

function studyDutyConflictsWithAppointment(studySessionDocs, startDate, endDate) {
  const startDateKey = dateKeyFromIstanbulDate(startDate);
  const startParts = getIstanbulDateParts(startDate);
  const startMinutes = startParts.hour * 60 + startParts.minute;
  const durationMinutes = Math.ceil(
    (endDate.getTime() - startDate.getTime()) / 60000
  );
  const endMinutes = startMinutes + durationMinutes;

  return studySessionDocs.some((doc) => {
    const data = doc.data();
    if (data.status !== "active" || data.slotDate !== startDateKey) {
      return false;
    }

    const slotStart = timeToMinutes(String(data.slotStart || ""));
    const slotEnd = timeToMinutes(String(data.slotEnd || ""));
    if (slotStart < 0 || slotEnd <= slotStart) {
      return false;
    }

    return intervalsOverlap(startMinutes, endMinutes, slotStart, slotEnd);
  });
}

function generateAppointmentStartOptions({
  dateKey,
  slot,
  durationMinutes,
  teacherAppointmentDocs,
  studentAppointmentDocs,
}) {
  const options = [];
  const baseDate = parseDateKeyToIstanbulNoon(dateKey);
  if (!baseDate) return options;

  const year = baseDate.getUTCFullYear();
  const month = String(baseDate.getUTCMonth() + 1).padStart(2, "0");
  const day = String(baseDate.getUTCDate()).padStart(2, "0");
  const plannedCapacity = plannedCapacityMinutesForSlot(slot);
  const usedCapacity = appointmentMinutesInSlot(
    teacherAppointmentDocs,
    buildSlotKey(dateKey, slot)
  );

  if (usedCapacity + durationMinutes > plannedCapacity) {
    return options;
  }

  for (
    let minute = slot.startMinutes;
    minute + durationMinutes <= slot.endMinutes;
    minute += APPOINTMENT_OPTION_STEP_MINUTES
  ) {
    const hourText = String(Math.floor(minute / 60)).padStart(2, "0");
    const minuteText = String(minute % 60).padStart(2, "0");
    const startDate = new Date(`${year}-${month}-${day}T${hourText}:${minuteText}:00+03:00`);
    const endDate = new Date(startDate.getTime() + durationMinutes * 60000);

    if (startDate.getTime() <= Date.now()) {
      continue;
    }

    if (appointmentOverlapsDocs(teacherAppointmentDocs, startDate, endDate)) {
      continue;
    }

    if (
      appointmentOverlapsDocs(
        studentAppointmentDocs,
        startDate,
        endDate,
        { bufferMinutes: APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES }
      )
    ) {
      continue;
    }

    options.push({
      start: `${hourText}:${minuteText}`,
      end: `${String(Math.floor((minute + durationMinutes) / 60)).padStart(2, "0")}:${String((minute + durationMinutes) % 60).padStart(2, "0")}`,
      scheduledStart: startDate.toISOString(),
      scheduledEnd: endDate.toISOString(),
    });
  }

  return options;
}

function queueCreatedAtMillis(queueData) {
  const createdAt = timestampToDate(queueData.createdAt);
  return createdAt ? createdAt.getTime() : null;
}

function compareQueuePriorityDocs(firstDoc, secondDoc) {
  const first = firstDoc.data();
  const second = secondDoc.data();
  const firstCreatedAt = queueCreatedAtMillis(first);
  const secondCreatedAt = queueCreatedAtMillis(second);

  if (firstCreatedAt === null && secondCreatedAt === null) return 0;
  if (firstCreatedAt === null) return 1;
  if (secondCreatedAt === null) return -1;

  return firstCreatedAt - secondCreatedAt;
}

function selectBestTeacher(candidates, activeQueueDocs, newQuestionCount) {
  const teacherLoad = new Map();

  for (const candidate of candidates) {
    teacherLoad.set(candidate.id, {
      teacher: candidate,
      estimatedLoad: 0,
      waitingCount: 0,
    });
  }

  for (const queueDoc of activeQueueDocs) {
    const queueData = queueDoc.data();
    const teacherId = queueData.teacherId;
    const load = teacherLoad.get(teacherId);
    if (!load) continue;

    const status = queueData.status;
    const weight = normalizeQuestionCount(queueData.questionCount);
    if (status === "waiting") {
      load.waitingCount += 1;
      load.estimatedLoad += weight;
    } else if (status === "in_progress") {
      load.estimatedLoad += weight;
    }
  }

  let loads = Array.from(teacherLoad.values());
  const belowSoftCap = loads.filter((item) => item.waitingCount < 3);

  if (belowSoftCap.length > 0) {
    loads = belowSoftCap;
  }

  loads.sort((a, b) => {
    if (a.estimatedLoad !== b.estimatedLoad) {
      return a.estimatedLoad - b.estimatedLoad;
    }

    if (a.waitingCount !== b.waitingCount) {
      return a.waitingCount - b.waitingCount;
    }

    return Math.random() < 0.5 ? -1 : 1;
  });

  const selected = loads[0] || null;
  if (!selected) return null;

  return {
    ...selected,
    nextEstimatedLoad: selected.estimatedLoad + newQuestionCount,
  };
}

async function assertRoleCaller(request, role) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Oturum doğrulanamadı."
    );
  }

  const userDoc = await db.collection("users").doc(request.auth.uid).get();

  if (!userDoc.exists || userDoc.data()?.role !== role) {
    throw new HttpsError(
      "permission-denied",
      "Bu işlem için yetkiniz yok."
    );
  }

  return {
    uid: request.auth.uid,
    data: userDoc.data() || {},
    ref: userDoc.ref,
  };
}

async function assertAuthenticatedUser(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Oturum doğrulanamadı."
    );
  }

  const userDoc = await db.collection("users").doc(request.auth.uid).get();

  if (!userDoc.exists) {
    throw new HttpsError(
      "permission-denied",
      "Bu işlem için yetkiniz yok."
    );
  }

  return {
    uid: request.auth.uid,
    data: userDoc.data() || {},
    ref: userDoc.ref,
  };
}

async function loadFutureScheduledAppointmentDocs(now = new Date()) {
  const snapshot = await db
    .collection("appointments")
    .where("status", "==", APPOINTMENT_STATUS_SCHEDULED)
    .where("scheduledStart", ">=", timestampFromDate(now))
    .orderBy("scheduledStart", "asc")
    .limit(500)
    .get();

  return snapshot.docs;
}

async function expireEndedScheduledAppointments(now = new Date()) {
  const result = {
    checkedCount: 0,
    expiredCount: 0,
  };

  while (true) {
    const snapshot = await db
      .collection("appointments")
      .where("status", "==", APPOINTMENT_STATUS_SCHEDULED)
      .where("scheduledEnd", "<=", timestampFromDate(now))
      .orderBy("scheduledEnd", "asc")
      .limit(100)
      .get();

    if (snapshot.empty) break;

    const batch = db.batch();
    let batchSize = 0;

    for (const appointmentDoc of snapshot.docs) {
      result.checkedCount += 1;

      if (!appointmentShouldExpireScheduled(appointmentDoc.data(), now)) {
        continue;
      }

      batch.update(appointmentDoc.ref, expiredAppointmentUpdate());
      batchSize += 1;
      result.expiredCount += 1;
    }

    if (batchSize > 0) {
      await batch.commit();
    }

    if (snapshot.size < 100) break;
  }

  return result;
}

async function findQueueActivityForStudentOnDate(studentId, dateKey) {
  const bounds = istanbulDayBoundsFromDateKey(dateKey);
  if (!studentId || !bounds) {
    return { verified: false };
  }

  const snapshot = await db.collection("queues")
    .where("studentId", "==", studentId)
    .where("createdAt", ">=", timestampFromDate(bounds.start))
    .where("createdAt", "<", timestampFromDate(bounds.end))
    .orderBy("createdAt", "asc")
    .limit(1)
    .get();

  return snapshot.empty
    ? { verified: false }
    : { verified: true, reason: "queue_activity" };
}

async function findStudyActivityForStudentOnDate(studentId, dateKey) {
  const bounds = istanbulDayBoundsFromDateKey(dateKey);
  if (!studentId || !bounds) {
    return { verified: false };
  }

  const snapshot = await db.collectionGroup("students")
    .where("studentId", "==", studentId)
    .where("checkedAt", ">=", timestampFromDate(bounds.start))
    .where("checkedAt", "<", timestampFromDate(bounds.end))
    .orderBy("checkedAt", "asc")
    .limit(5)
    .get();

  const hasParticipation = snapshot.docs.some((doc) => {
    const status = cleanText(doc.data().status || "present");
    return ["present", "left", "completed"].includes(status);
  });

  return hasParticipation
    ? { verified: true, reason: "study_activity" }
    : { verified: false };
}

async function findInstitutionActivityForStudentOnDate(studentId, dateKey) {
  const queueActivity =
    await findQueueActivityForStudentOnDate(studentId, dateKey);
  if (queueActivity.verified) return queueActivity;

  return findStudyActivityForStudentOnDate(studentId, dateKey);
}

async function reconcileNoShowAppointmentDocs(
  pendingDocs,
  findActivityForStudent = findInstitutionActivityForStudentOnDate,
  activityCache = new Map()
) {
  const result = {
    checkedCount: pendingDocs.length,
    verifiedCount: 0,
    unverifiedCount: 0,
    failedCount: 0,
    uniqueStudentLookups: 0,
  };

  for (const doc of pendingDocs) {
    try {
      const data = doc.data() || {};

      if (
        data.status !== "no_show" ||
        data.noShowVerificationStatus !== NO_SHOW_VERIFICATION_PENDING
      ) {
        continue;
      }

      const studentId = cleanText(data.studentId);
      const dateKey = cleanText(data.dateKey);
      const cacheKey = `${studentId}|${dateKey}`;

      if (!activityCache.has(cacheKey)) {
        result.uniqueStudentLookups += 1;
        activityCache.set(
          cacheKey,
          await findActivityForStudent(studentId, dateKey)
        );
      }

      const activity = activityCache.get(cacheKey);
      await doc.ref.update(noShowVerificationUpdate(activity));

      if (activity?.verified) {
        result.verifiedCount += 1;
      } else {
        result.unverifiedCount += 1;
      }
    } catch (error) {
      result.failedCount += 1;
      console.error("No-show verification record failed.", {
        appointmentId: doc.id,
        error,
      });
    }
  }

  return result;
}

function noShowReconciliationCanWriteMarker(result, remainingPendingCount) {
  return result.failedCount === 0 && remainingPendingCount === 0;
}

async function reconcileNoShowsAtDayEnd(now = new Date()) {
  const runtimeRef = db.collection("settings").doc("runtimeState");
  const runtimeDoc = await runtimeRef.get();
  const runtimeData = runtimeDoc.data() || {};

  if (
    !shouldRunNoShowReconciliation(
      now,
      cleanText(runtimeData.lastNoShowReconciliationDateKey)
    )
  ) {
    return { skipped: true };
  }

  const dateKey = getIstanbulDateParts(now).dateKey;
  const pendingQuery = db.collection("appointments")
    .where("status", "==", "no_show")
    .where("dateKey", "==", dateKey)
    .where(
      "noShowVerificationStatus",
      "==",
      NO_SHOW_VERIFICATION_PENDING
    );
  const activityCache = new Map();
  const result = {
    checkedCount: 0,
    verifiedCount: 0,
    unverifiedCount: 0,
    failedCount: 0,
    uniqueStudentLookups: 0,
  };

  while (true) {
    const pendingSnapshot = await pendingQuery.limit(100).get();
    if (pendingSnapshot.empty) break;

    const batchResult = await reconcileNoShowAppointmentDocs(
      pendingSnapshot.docs,
      findInstitutionActivityForStudentOnDate,
      activityCache
    );
    result.checkedCount += batchResult.checkedCount;
    result.verifiedCount += batchResult.verifiedCount;
    result.unverifiedCount += batchResult.unverifiedCount;
    result.failedCount += batchResult.failedCount;
    result.uniqueStudentLookups += batchResult.uniqueStudentLookups;

    if (batchResult.failedCount > 0 || pendingSnapshot.size < 100) break;
  }

  const remainingPendingSnapshot = await pendingQuery.limit(1).get();
  const remainingPendingCount = remainingPendingSnapshot.size;

  if (noShowReconciliationCanWriteMarker(result, remainingPendingCount)) {
    await runtimeRef.set({
      lastNoShowReconciliationDateKey: dateKey,
      lastNoShowReconciledAt: fieldValue.serverTimestamp(),
      lastNoShowReconciliationCheckedCount: result.checkedCount,
      lastNoShowReconciliationVerifiedCount: result.verifiedCount,
      lastNoShowReconciliationUnverifiedCount: result.unverifiedCount,
    }, { merge: true });
  }

  return {
    skipped: false,
    dateKey,
    remainingPendingCount,
    ...result,
  };
}

async function startNextWaitingQueueInTransaction(transaction, teacherId) {
  const activeSnapshot = await transaction.get(
    db.collection("queues")
      .where("teacherId", "==", teacherId)
      .where("status", "==", "in_progress")
      .limit(1)
  );

  if (!activeSnapshot.empty) {
    return null;
  }

  const waitingSnapshot = await transaction.get(
    db.collection("queues")
      .where("teacherId", "==", teacherId)
      .where("status", "==", "waiting")
  );

  if (waitingSnapshot.empty) {
    return null;
  }

  const waitingQueues = waitingSnapshot.docs
    .sort((a, b) => compareQueuePriorityDocs(a, b));
  const nextQueue = waitingQueues[0];

  transaction.update(nextQueue.ref, {
    status: "in_progress",
    startedAt: fieldValue.serverTimestamp(),
    updatedAt: fieldValue.serverTimestamp(),
  });

  return nextQueue.id;
}

function selectNextWaitingQueueDoc(waitingDocs, excludeQueueId = null) {
  const waitingQueues = waitingDocs
    .filter((doc) => doc.id !== excludeQueueId)
    .sort((a, b) => compareQueuePriorityDocs(a, b));

  return waitingQueues[0] || null;
}

function assertQueueRuntimeOpen(scheduleData, runtimeData, now = new Date()) {
  const runtimeState = buildEffectiveRuntimeState(
    scheduleData,
    runtimeData,
    now
  );

  if (runtimeState.institutionMode !== "active") {
    throw new HttpsError(
      "failed-precondition",
      "Kurum şu anda sıra alımına kapalı."
    );
  }

  if (runtimeState.isLunchBreak) {
    throw new HttpsError(
      "failed-precondition",
      "Öğle arasında zümre sırası alınamaz."
    );
  }

  if (!runtimeState.isZumreOpen) {
    throw new HttpsError(
      "failed-precondition",
      "Zümre saati dışında sıra alınamaz."
    );
  }
}

function validateUserPayload(data, options = {}) {
  const username = normalizeUsername(data?.username);
  const email = emailFromUsername(username);
  const role = cleanText(data?.role);
  const password = String(data?.password || "");
  const firstName = cleanText(data?.name);
  const surname = cleanText(data?.surname);
  const fullName = cleanText(data?.fullName || `${firstName} ${surname}`);

  if (!username) {
    throw new HttpsError(
      "invalid-argument",
      "Kullanıcı adı zorunludur."
    );
  }

  if (!USER_ROLES.includes(role)) {
    throw new HttpsError(
      "invalid-argument",
      "Geçersiz kullanıcı rolü."
    );
  }

  if (!firstName || !surname) {
    throw new HttpsError(
      "invalid-argument",
      "Ad ve soyad zorunludur."
    );
  }

  if (options.requirePassword && password.length < 6) {
    throw new HttpsError(
      "invalid-argument",
      "Şifre en az 6 karakter olmalıdır."
    );
  }

  return {
    email,
    username,
    identityKey: username,
    password,
    name: firstName,
    surname,
    fullName,
    role,
    subjects: cleanSubjects(data?.subjects),
    className: cleanText(data?.className),
    branch: cleanText(data?.branch),
    department: cleanText(data?.department),
    studentNo: cleanText(data?.studentNo),
  };
}

function buildUserDocument(payload, options = {}) {
  const userData = {
    uid: options.uid,
    email: payload.email,
    username: payload.username,
    identityKey: payload.identityKey,
    name: payload.name,
    surname: payload.surname,
    fullName: payload.fullName,
    role: payload.role,
    updatedAt: fieldValue.serverTimestamp(),
  };

  if (options.includeCreatedAt) {
    userData.createdAt = fieldValue.serverTimestamp();
  }

  if (payload.role === "student") {
    Object.assign(userData, {
      className: payload.className,
      branch: payload.branch,
      department: payload.department,
      studentNo: payload.studentNo,
      isInStudySession: false,
      activeStudySessionId: null,
    });
  }

  if (payload.role === "teacher") {
    Object.assign(userData, {
      subjects: payload.subjects,
      branch: payload.subjects[0] || "",
      teacherStatus: options.existingTeacherStatus || "absent",
      weeklyAvailability: options.existingWeeklyAvailability || {},
    });
  }

  return userData;
}

function applyRoleCleanup(updateData, newRole) {
  if (newRole === "teacher") {
    updateData.className = fieldValue.delete();
    updateData.department = fieldValue.delete();
    updateData.studentNo = fieldValue.delete();
    updateData.isInStudySession = fieldValue.delete();
    updateData.activeStudySessionId = fieldValue.delete();
    updateData.manualAbsentDate = fieldValue.delete();
    updateData.breakUntil = fieldValue.delete();
  } else if (newRole === "student") {
    updateData.subjects = fieldValue.delete();
    updateData.teacherStatus = fieldValue.delete();
    updateData.weeklyAvailability = fieldValue.delete();
    updateData.manualAbsentDate = fieldValue.delete();
    updateData.breakUntil = fieldValue.delete();
  } else {
    updateData.subjects = fieldValue.delete();
    updateData.teacherStatus = fieldValue.delete();
    updateData.weeklyAvailability = fieldValue.delete();
    updateData.manualAbsentDate = fieldValue.delete();
    updateData.breakUntil = fieldValue.delete();
    updateData.className = fieldValue.delete();
    updateData.branch = fieldValue.delete();
    updateData.department = fieldValue.delete();
    updateData.studentNo = fieldValue.delete();
    updateData.isInStudySession = fieldValue.delete();
    updateData.activeStudySessionId = fieldValue.delete();
  }
}

function mapAuthError(error, fallbackMessage) {
  const code = error?.code || "";

  if (code === "auth/email-already-exists") {
    return "Bu kullanıcı adı zaten kullanılıyor.";
  }

  if (code === "auth/user-not-found") {
    return "Kullanıcı hesabı bulunamadı.";
  }

  if (code === "auth/invalid-password" || code === "auth/weak-password") {
    return "Şifre en az 6 karakter olmalıdır.";
  }

  if (code === "auth/invalid-email") {
    return "Kullanıcı adı geçerli bir e-posta oluşturamıyor.";
  }

  return fallbackMessage || "Kullanıcı işlemi tamamlanamadı.";
}

function mapUserLifecycleErrorCode(error) {
  const code = error?.code || "";

  if (
    code === "auth/email-already-exists" ||
    code === "already-exists" ||
    code === 6
  ) {
    return "already-exists";
  }

  if (code === "auth/user-not-found" || code === "not-found" || code === 5) {
    return "not-found";
  }

  if (
    code === "auth/invalid-password" ||
    code === "auth/weak-password" ||
    code === "auth/invalid-email" ||
    code === "invalid-argument" ||
    code === 3
  ) {
    return "invalid-argument";
  }

  if (
    code === "auth/insufficient-permission" ||
    code === "permission-denied" ||
    code === 7
  ) {
    return "permission-denied";
  }

  return "internal";
}

async function hasActiveQueueFor(uid, fieldName) {
  const snapshot = await db
    .collection("queues")
    .where("status", "in", ["waiting", "in_progress"])
    .get();

  return snapshot.docs.some(
    (doc) => doc.data()?.[fieldName] === uid
  );
}

async function hasActiveStudySessionFor(uid, fieldName) {
  const snapshot = await db
    .collection("studySessions")
    .where("status", "==", "active")
    .get();

  return snapshot.docs.some(
    (doc) => doc.data()?.[fieldName] === uid
  );
}

async function assertNoActiveUserOperation(uid, userData) {
  const role = userData?.role;

  if (role === "student") {
    if (
      userData.isInStudySession === true ||
      userData.activeStudySessionId ||
      await hasActiveQueueFor(uid, "studentId")
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Bu öğrencinin aktif bir işlemi bulunuyor. Önce işlemi sonlandırın."
      );
    }
  }

  if (role === "teacher") {
    if (
      userData.teacherStatus === "studyGuard" ||
      await hasActiveQueueFor(uid, "teacherId") ||
      await hasActiveStudySessionFor(uid, "dutyTeacherId")
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Bu öğretmenin aktif bir işlemi bulunuyor. Önce işlemi sonlandırın."
      );
    }
  }

  if (role === "studyGuard") {
    if (await hasActiveStudySessionFor(uid, "staffId")) {
      throw new HttpsError(
        "failed-precondition",
        "Bu kullanıcının aktif bir etüt oturumu bulunuyor. Önce işlemi sonlandırın."
      );
    }
  }
}

async function loadUserDeleteGuardContext() {
  const [activeQueuesSnapshot, activeSessionsSnapshot, adminsSnapshot] =
    await Promise.all([
      db
        .collection("queues")
        .where("status", "in", ["waiting", "in_progress"])
        .get(),
      db
        .collection("studySessions")
        .where("status", "==", "active")
        .get(),
      db
        .collection("users")
        .where("role", "==", "admin")
        .limit(2)
        .get(),
    ]);

  return {
    activeQueues: activeQueuesSnapshot.docs,
    activeStudySessions: activeSessionsSnapshot.docs,
    hasMultipleAdmins: adminsSnapshot.size > 1,
  };
}

function hasContextMatch(docs, fieldName, uid) {
  return docs.some((doc) => doc.data()?.[fieldName] === uid);
}

function getDeleteBlockReason(uid, userData, guardContext, adminUid) {
  const role = userData?.role;

  if (uid === adminUid) {
    return "Kendi yönetici hesabınız silinemez.";
  }

  if (role === "admin" && !guardContext.hasMultipleAdmins) {
    return "Sistemdeki son yönetici hesabı silinemez.";
  }

  if (role === "student") {
    if (userData.isInStudySession === true || userData.activeStudySessionId) {
      return "aktif etüt";
    }

    if (hasContextMatch(guardContext.activeQueues, "studentId", uid)) {
      return "aktif zümre sırası";
    }
  }

  if (role === "teacher") {
    if (userData.teacherStatus === "studyGuard") {
      return "aktif etüt görevi";
    }

    if (hasContextMatch(guardContext.activeQueues, "teacherId", uid)) {
      return "aktif zümre sırası";
    }

    if (hasContextMatch(guardContext.activeStudySessions, "dutyTeacherId", uid)) {
      return "aktif etüt branş öğretmeni";
    }
  }

  if (
    role === "studyGuard" &&
    hasContextMatch(guardContext.activeStudySessions, "staffId", uid)
  ) {
    return "aktif etüt oturumu";
  }

  return null;
}

function displayNameForUser(uid, userData) {
  const fullName = cleanText(userData?.fullName);
  const email = cleanText(userData?.email);
  const username = cleanText(userData?.username);

  return fullName || email || username || uid;
}

function bulkErrorResult(uid, userData, error) {
  const reason = error instanceof HttpsError
    ? error.message
    : mapAuthError(error, "Kullanıcı silinemedi.");

  return {
    uid,
    name: displayNameForUser(uid, userData),
    email: cleanText(userData?.email),
    status: "failed",
    reason,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isAuthDeleteQuotaError(error) {
  const code = String(error?.code || "").toLowerCase();
  const message = String(error?.message || "").toLowerCase();

  return code.includes("quota") || message.includes("quota");
}

async function deleteAuthUserWithRetry(uid) {
  let lastError = null;

  for (let attempt = 0; attempt <= AUTH_DELETE_RETRY_DELAYS_MS.length; attempt += 1) {
    try {
      await admin.auth().deleteUser(uid);
      return;
    } catch (error) {
      if (error?.code === "auth/user-not-found") {
        throw error;
      }

      lastError = error;

      if (!isAuthDeleteQuotaError(error) || attempt === AUTH_DELETE_RETRY_DELAYS_MS.length) {
        break;
      }

      await sleep(AUTH_DELETE_RETRY_DELAYS_MS[attempt]);
    }
  }

  throw lastError;
}

async function deleteUserLifecycle(uid, adminUid, guardContext) {
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();

  if (!userDoc.exists) {
    return {
      uid,
      name: uid,
      email: "",
      status: "failed",
      reason: "Kullanıcı kaydı bulunamadı.",
    };
  }

  const userData = userDoc.data() || {};
  const blockedReason = getDeleteBlockReason(
    uid,
    userData,
    guardContext,
    adminUid
  );

  if (blockedReason) {
    return {
      uid,
      name: displayNameForUser(uid, userData),
      email: cleanText(userData.email),
      status: "skipped",
      reason: blockedReason,
    };
  }

  try {
    try {
      await deleteAuthUserWithRetry(uid);
    } catch (authError) {
      if (authError?.code !== "auth/user-not-found") {
        throw authError;
      }

      console.warn("adminDeleteUser auth user not found", {
        adminUid,
        targetUid: uid,
      });
    }

    await userRef.delete();

    console.log("admin user lifecycle", {
      operation: "delete",
      adminUid,
      targetUid: uid,
    });

    return {
      uid,
      name: displayNameForUser(uid, userData),
      email: cleanText(userData.email),
      status: "deleted",
      reason: "",
    };
  } catch (error) {
    console.error("adminDeleteUser error", {
      adminUid,
      targetUid: uid,
      error: error?.message || error,
    });

    return bulkErrorResult(uid, userData, error);
  }
}

exports.adminCreateUser = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const payload = validateUserPayload(request.data, {
      requirePassword: true,
    });

    let authUser;

    try {
      authUser = await admin.auth().createUser({
        email: payload.email,
        password: payload.password,
        displayName: payload.fullName,
        disabled: false,
      });

      const userData = buildUserDocument(payload, {
        uid: authUser.uid,
        includeCreatedAt: true,
      });

      await db.collection("users").doc(authUser.uid).create(userData);

      console.log("admin user lifecycle", {
        operation: "create",
        adminUid,
        targetUid: authUser.uid,
      });

      return {
        ok: true,
        uid: authUser.uid,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      if (authUser?.uid) {
        try {
          await admin.auth().deleteUser(authUser.uid);
        } catch (rollbackError) {
          console.error("adminCreateUser rollback failed", {
            adminUid,
            targetUid: authUser.uid,
            error: rollbackError?.message || rollbackError,
          });
        }
      }

      console.error("adminCreateUser error", {
        adminUid,
        error: error?.message || error,
      });

      throw new HttpsError(
        mapUserLifecycleErrorCode(error),
        mapAuthError(error, "Kullanıcı oluşturulamadı.")
      );
    }
  }
);

exports.adminUpdateUser = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = cleanText(request.data?.uid);

    if (!uid) {
      throw new HttpsError(
        "invalid-argument",
        "Kullanıcı kimliği eksik."
      );
    }

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Kullanıcı kaydı bulunamadı."
      );
    }

    const existingData = userDoc.data() || {};
    const payload = validateUserPayload(request.data);
    const roleChanged = payload.role !== existingData.role;
    const emailChanged = payload.email !== existingData.email;
    const oldEmail = existingData.email;

    if (roleChanged) {
      await assertNoActiveUserOperation(uid, existingData);
    }

    try {
      if (emailChanged) {
        await admin.auth().updateUser(uid, {
          email: payload.email,
        });
      }

      const updateData = buildUserDocument(payload, {
        uid,
        existingTeacherStatus: existingData.teacherStatus || "absent",
        existingWeeklyAvailability: existingData.weeklyAvailability || {},
      });

      applyRoleCleanup(updateData, payload.role);

      await userRef.update(updateData);

      console.log("admin user lifecycle", {
        operation: "update",
        adminUid,
        targetUid: uid,
      });

      return {
        ok: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      if (emailChanged && oldEmail) {
        try {
          await admin.auth().updateUser(uid, {
            email: oldEmail,
          });
        } catch (rollbackError) {
          console.error("adminUpdateUser auth rollback failed", {
            adminUid,
            targetUid: uid,
            error: rollbackError?.message || rollbackError,
          });
        }
      }

      console.error("adminUpdateUser error", {
        adminUid,
        targetUid: uid,
        error: error?.message || error,
      });

      throw new HttpsError(
        mapUserLifecycleErrorCode(error),
        mapAuthError(error, "Kullanıcı güncellenemedi.")
      );
    }
  }
);

exports.adminDeleteUser = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const uid = cleanText(request.data?.uid);

    if (!uid) {
      throw new HttpsError(
        "invalid-argument",
        "Kullanıcı kimliği eksik."
      );
    }

    if (uid === adminUid) {
      throw new HttpsError(
        "failed-precondition",
        "Kendi yönetici hesabınızı buradan silemezsiniz."
      );
    }

    try {
      const result = await deleteUserLifecycle(
        uid,
        adminUid,
        await loadUserDeleteGuardContext()
      );

      if (result.status === "skipped") {
        throw new HttpsError(
          "failed-precondition",
          result.reason || "Kullanıcı aktif işlem nedeniyle silinemedi."
        );
      }

      if (result.status === "failed") {
        throw new HttpsError(
          result.reason === "Kullanıcı kaydı bulunamadı."
            ? "not-found"
            : "internal",
          result.reason || "Kullanıcı silinemedi."
        );
      }

      return {
        ok: true,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }

      console.error("adminDeleteUser error", {
        adminUid,
        targetUid: uid,
        error: error?.message || error,
      });

      throw new HttpsError(
        mapUserLifecycleErrorCode(error),
        mapAuthError(error, "Kullanıcı silinemedi.")
      );
    }
  }
);

exports.adminBulkDeleteUsers = onCall(
  {
    region: REGION,
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const rawTargetUids = request.data?.targetUids;

    if (!Array.isArray(rawTargetUids)) {
      throw new HttpsError(
        "invalid-argument",
        "Silinecek kullanıcı listesi eksik."
      );
    }

    const targetUids = Array.from(
      new Set(
        rawTargetUids
          .map((uid) => cleanText(uid))
          .filter((uid) => uid.length > 0)
      )
    );

    if (targetUids.length === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Silinecek kullanıcı seçilmedi."
      );
    }

    if (targetUids.length > BULK_DELETE_LIMIT) {
      throw new HttpsError(
        "invalid-argument",
        `Tek seferde en fazla ${BULK_DELETE_LIMIT} kullanıcı silinebilir.`
      );
    }

    const results = [];

    for (let index = 0; index < targetUids.length; index += BULK_DELETE_CHUNK_SIZE) {
      const chunk = targetUids.slice(index, index + BULK_DELETE_CHUNK_SIZE);
      const guardContext = await loadUserDeleteGuardContext();
      const chunkResults = await Promise.all(
        chunk.map((uid) => deleteUserLifecycle(uid, adminUid, guardContext))
      );

      results.push(...chunkResults);
    }

    const deleted = results.filter((item) => item.status === "deleted");
    const skipped = results.filter((item) => item.status === "skipped");
    const failed = results.filter((item) => item.status === "failed");

    console.log("admin user lifecycle", {
      operation: "bulk-delete",
      adminUid,
      requestedCount: targetUids.length,
      deletedCount: deleted.length,
      skippedCount: skipped.length,
      failedCount: failed.length,
    });

    return {
      ok: failed.length === 0,
      requestedCount: targetUids.length,
      deletedCount: deleted.length,
      skippedCount: skipped.length,
      failedCount: failed.length,
      results,
    };
  }
);

exports.updateUserPassword = onCall(
  {
    region: REGION,
  },
  async (request) => {
    try {
      const adminUid = await assertAdminCaller(request);

      const uid = request.data?.uid;
      const password = request.data?.password;

      if (
        typeof uid !== "string" ||
        uid.trim() === "" ||
        typeof password !== "string" ||
        password.length < 6
      ) {
        throw new HttpsError(
          "invalid-argument",
          "Şifre en az 6 karakter olmalıdır."
        );
      }

      await admin.auth().updateUser(uid.trim(), {
        password,
      });

      if (uid.trim() !== adminUid) {
        await admin.auth().revokeRefreshTokens(uid.trim());
      }

      console.log("admin user lifecycle", {
        operation: "password-reset",
        adminUid,
        targetUid: uid.trim(),
        revokedRefreshTokens: uid.trim() !== adminUid,
      });

      return {
        success: true,
        message: "Şifre güncellendi.",
      };
    } catch (error) {
      console.error("updateUserPassword error:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        mapUserLifecycleErrorCode(error),
        mapAuthError(error, "Şifre güncellenemedi.")
      );
    }
  }
);

exports.setInstitutionMode = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const mode = cleanText(request.data?.mode).toLowerCase();
    const runtimeRef = db.collection("settings").doc("runtimeState");
    const now = new Date();
    const scheduleDoc = await db
      .collection("settings")
      .doc("zumreSchedule")
      .get();
    const scheduleData = scheduleDoc.data() || {};

    if (!["active", "closed", "exam"].includes(mode)) {
      throw new HttpsError(
        "invalid-argument",
        "Geçersiz kurum modu."
      );
    }

    if (mode === "active") {
      const runtimeState = buildEffectiveRuntimeState(
        scheduleData,
        { institutionMode: "active" },
        now
      );

      await runtimeRef.set(
        {
          ...runtimeState,
          closedDate: null,
          examStartedAt: null,
          examEndsAt: null,
          plannedExamId: null,
          updatedAt: fieldValue.serverTimestamp(),
          updatedBy: adminUid,
        },
        { merge: true }
      );

      const plannedExamResult = await completeActivePlannedExams(now, adminUid);

      return {
        ok: true,
        mode: "active",
        completedPlannedExams: plannedExamResult.completedCount,
      };
    }

    if (mode === "closed") {
      const closedDate = getIstanbulDateParts(now).dateKey;
      const runtimeState = buildEffectiveRuntimeState(
        scheduleData,
        {
          institutionMode: "closed",
          closedDate,
        },
        now
      );

      await runtimeRef.set(
        {
          ...runtimeState,
          examStartedAt: null,
          updatedAt: fieldValue.serverTimestamp(),
          updatedBy: adminUid,
        },
        { merge: true }
      );

      await deleteWaitingZumreQueuesWhenClosed({}, now, {
        forceClosed: true,
      });

      return { ok: true, mode: "closed" };
    }

    const examType = cleanText(request.data?.examType).toLowerCase();
    const durationMinutes =
      examType === "tyt" ? 165 : examType === "ayt" ? 180 : 0;

    if (durationMinutes === 0) {
      throw new HttpsError(
        "invalid-argument",
        "Deneme türü TYT veya AYT olmalıdır."
      );
    }

    const startTimestamp = admin.firestore.Timestamp.now();
    const endTimestamp = admin.firestore.Timestamp.fromMillis(
      startTimestamp.toMillis() + durationMinutes * 60 * 1000
    );
    const runtimeState = buildEffectiveRuntimeState(
      scheduleData,
      {
        institutionMode: "exam",
        examType,
        examEndsAt: endTimestamp,
      },
      now
    );

    await runtimeRef.set(
      {
        ...runtimeState,
        closedDate: null,
        examStartedAt: startTimestamp,
        updatedAt: fieldValue.serverTimestamp(),
        updatedBy: adminUid,
      },
      { merge: true }
    );

    await deleteWaitingZumreQueuesWhenClosed({}, now, {
      forceClosed: true,
    });
    const studyCloseResult = await closeActiveStudySessionsForInstitutionMode();

    return {
      ok: true,
      mode: "exam",
      examType,
      examEndsAt: endTimestamp.toDate().toISOString(),
      closedStudySessions: studyCloseResult.closedCount,
    };
  }
);

exports.previewZumreScheduleChange = onCall(
  {
    region: REGION,
  },
  async (request) => {
    await assertAdminCaller(request);
    const weeklySchedule = request.data?.weeklySchedule;
    if (!weeklySchedule || typeof weeklySchedule !== "object") {
      throw new HttpsError("invalid-argument", "Haftalık program eksik.");
    }

    const now = new Date();
    const scheduleDoc = await db.collection("settings").doc("zumreSchedule").get();
    const conflictDocs = scheduleConflictDocsForChange({
      appointmentDocs: await loadFutureScheduledAppointmentDocs(now),
      oldScheduleData: scheduleDoc.data() || {},
      newWeeklySchedule: weeklySchedule,
      now,
    });

    return {
      ok: true,
      conflictCount: conflictDocs.length,
      conflicts: summarizeAppointmentConflicts(conflictDocs),
    };
  }
);

exports.applyZumreScheduleChange = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const weeklySchedule = request.data?.weeklySchedule;
    const confirm = request.data?.confirm === true;
    if (!weeklySchedule || typeof weeklySchedule !== "object") {
      throw new HttpsError("invalid-argument", "Haftalık program eksik.");
    }

    const scheduleRef = db.collection("settings").doc("zumreSchedule");
    const now = new Date();
    const scheduleDoc = await scheduleRef.get();
    const scheduleData = scheduleDoc.data() || {};
    const conflictDocs = scheduleConflictDocsForChange({
      appointmentDocs: await loadFutureScheduledAppointmentDocs(now),
      oldScheduleData: scheduleData,
      newWeeklySchedule: weeklySchedule,
      now,
    });

    if (conflictDocs.length > 0 && !confirm) {
      return {
        ok: true,
        requiresConfirm: true,
        conflictCount: conflictDocs.length,
        conflicts: summarizeAppointmentConflicts(conflictDocs),
      };
    }

    let batch = db.batch();
    let batchSize = 0;

    batch.set(scheduleRef, {
      weeklySchedule: normalizeWeeklySchedule(weeklySchedule),
      updatedAt: fieldValue.serverTimestamp(),
      updatedBy: adminUid,
    }, { merge: true });
    batchSize += 1;

    for (const doc of conflictDocs) {
      batch.update(doc.ref, {
        status: "cancelled",
        cancelledAt: fieldValue.serverTimestamp(),
        cancelledBy: adminUid,
        cancelledByRole: "admin",
        cancelReason: "schedule_changed",
        updatedAt: fieldValue.serverTimestamp(),
      });
      batchSize += 1;

      if (batchSize >= 400) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }

    if (batchSize > 0) {
      await batch.commit();
    }

    return {
      ok: true,
      cancelledCount: conflictDocs.length,
      conflicts: summarizeAppointmentConflicts(conflictDocs),
    };
  }
);

exports.createPlannedExam = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const examType = cleanText(request.data?.examType).toLowerCase();
    const requestedExamId = cleanText(request.data?.examId);
    const durationMinutes = plannedExamDurationMinutes(examType);
    const confirm = request.data?.confirm === true;
    const scheduledStart = parseRequestedPlannedExamStart(request.data || {});

    if (!durationMinutes) {
      throw new HttpsError("invalid-argument", "Deneme türü TYT veya AYT olmalıdır.");
    }

    if (!scheduledStart || scheduledStart.getTime() <= Date.now()) {
      throw new HttpsError("failed-precondition", "Planlı deneme başlangıcı gelecek bir saat olmalıdır.");
    }

    const scheduledEnd = new Date(scheduledStart.getTime() + durationMinutes * 60000);
    const conflictDocs = plannedExamConflictDocs(
      await loadFutureScheduledAppointmentDocs(new Date()),
      scheduledStart,
      scheduledEnd
    );

    if (conflictDocs.length > 0 && !confirm) {
      return {
        ok: true,
        requiresConfirm: true,
        conflictCount: conflictDocs.length,
        conflicts: summarizeAppointmentConflicts(conflictDocs),
        scheduledEnd: scheduledEnd.toISOString(),
      };
    }

    const plannedExamRef = db.collection("settings").doc("plannedExam");
    const plannedExamDoc = await plannedExamRef.get();
    const currentData = plannedExamDoc.data() || {};
    const currentItems = plannedExamItems(currentData)
      .filter((item) => item.end.getTime() > Date.now())
      .filter((item) => !requestedExamId || item.id !== requestedExamId)
      .map(publicPlannedExamItem);

    const hasExamOverlap = plannedExamItems({ items: currentItems }).some(
      (item) =>
        intervalsOverlap(
          scheduledStart.getTime(),
          scheduledEnd.getTime(),
          item.start.getTime(),
          item.end.getTime()
        )
    );
    if (hasExamOverlap) {
      throw new HttpsError(
        "already-exists",
        "Bu saat aralığında başka bir planlı deneme var."
      );
    }

    let batch = db.batch();
    let batchSize = 0;
    const examId = requestedExamId || `exam_${crypto.randomUUID()}`;
    const newItem = {
      id: examId,
      status: PLANNED_EXAM_STATUS_SCHEDULED,
      examType,
      scheduledStart: timestampFromDate(scheduledStart),
      scheduledEnd: timestampFromDate(scheduledEnd),
    };
    const nextItems = [...currentItems, newItem]
      .sort((a, b) =>
        timestampToDate(a.scheduledStart).getTime() -
        timestampToDate(b.scheduledStart).getTime()
      );

    batch.set(plannedExamRef, {
      ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
      items: nextItems,
      createdAt: fieldValue.serverTimestamp(),
      createdBy: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });
    batchSize += 1;

    for (const doc of conflictDocs) {
      batch.update(doc.ref, {
        status: "cancelled",
        cancelledAt: fieldValue.serverTimestamp(),
        cancelledBy: adminUid,
        cancelledByRole: "admin",
        cancelReason: "exam_scheduled",
        updatedAt: fieldValue.serverTimestamp(),
      });
      batchSize += 1;

      if (batchSize >= 400) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }

    if (batchSize > 0) {
      await batch.commit();
    }

    return {
      ok: true,
      examId,
      examType,
      scheduledStart: scheduledStart.toISOString(),
      scheduledEnd: scheduledEnd.toISOString(),
      cancelledCount: conflictDocs.length,
    };
  }
);

exports.cancelPlannedExam = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const examId = cleanText(request.data?.examId);
    const plannedExamRef = db.collection("settings").doc("plannedExam");
    const plannedExamDoc = await plannedExamRef.get();

    if (!plannedExamDoc.exists) {
      return { ok: true, cancelled: false };
    }

    const plannedExamData = plannedExamDoc.data() || {};
    const items = plannedExamItems(plannedExamData);
    const targetId = examId || items[0]?.id || "";
    const target = items.find((item) => item.id === targetId);

    if (!target) {
      return { ok: true, cancelled: false };
    }

    if (target.status !== PLANNED_EXAM_STATUS_SCHEDULED) {
      throw new HttpsError(
        "failed-precondition",
        "Yalnızca henüz başlamamış planlı deneme iptal edilebilir."
      );
    }

    const nextItems = items
      .filter((item) => item.id !== targetId)
      .map(publicPlannedExamItem);

    await plannedExamRef.set({
      ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
      items: nextItems,
      cancelledAt: fieldValue.serverTimestamp(),
      cancelledBy: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, cancelled: true, examId: targetId };
  }
);

exports.startPlannedExamNow = onCall(
  {
    region: REGION,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request) => {
    const adminUid = await assertAdminCaller(request);
    const requestedExamId = cleanText(request.data?.examId);
    const now = new Date();
    const plannedExamRef = db.collection("settings").doc("plannedExam");
    const runtimeRef = db.collection("settings").doc("runtimeState");

    const [
      plannedExamDoc,
      scheduleDoc,
      futureAppointments,
    ] = await Promise.all([
      plannedExamRef.get(),
      db.collection("settings").doc("zumreSchedule").get(),
      loadFutureScheduledAppointmentDocs(now),
    ]);

    if (!plannedExamDoc.exists) {
      throw new HttpsError("not-found", "Planlı deneme bulunamadı.");
    }

    const plannedExamData = plannedExamDoc.data() || {};
    const items = plannedExamItems(plannedExamData);
    const targetId = requestedExamId || items[0]?.id || "";
    const target = items.find((item) => item.id === targetId);

    if (!target) {
      throw new HttpsError("not-found", "Planlı deneme bulunamadı.");
    }

    if (target.status !== PLANNED_EXAM_STATUS_SCHEDULED) {
      throw new HttpsError(
        "failed-precondition",
        "Yalnızca henüz başlamamış planlı deneme şimdi başlatılabilir."
      );
    }

    const examType = target.examType;
    const durationMinutes = plannedExamDurationMinutes(examType);
    if (!durationMinutes) {
      throw new HttpsError("failed-precondition", "Planlı deneme türü geçersiz.");
    }

    const scheduledEnd = new Date(now.getTime() + durationMinutes * 60000);
    const conflictDocs = plannedExamConflictDocs(
      futureAppointments,
      now,
      scheduledEnd
    );
    const startTimestamp = timestampFromDate(now);
    const endTimestamp = timestampFromDate(scheduledEnd);
    const scheduleData = scheduleDoc.data() || {};
    const runtimeState = buildEffectiveRuntimeState(
      scheduleData,
      {
        institutionMode: "exam",
        examType,
        examEndsAt: endTimestamp,
      },
      now
    );

    let batch = db.batch();
    let batchSize = 0;

    batch.set(runtimeRef, {
      ...runtimeState,
      closedDate: null,
      examStartedAt: startTimestamp,
      updatedAt: fieldValue.serverTimestamp(),
      updatedBy: adminUid,
    }, { merge: true });
    batchSize += 1;

    const nextItems = items.map((item) =>
      item.id === targetId
        ? publicPlannedExamItem({
          ...item,
          status: PLANNED_EXAM_STATUS_ACTIVE,
          scheduledStart: startTimestamp,
          scheduledEnd: endTimestamp,
        })
        : publicPlannedExamItem(item)
    );

    batch.set(plannedExamRef, {
      ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
      status: PLANNED_EXAM_STATUS_ACTIVE,
      examType,
      scheduledStart: startTimestamp,
      scheduledEnd: endTimestamp,
      items: nextItems,
      startedAt: fieldValue.serverTimestamp(),
      startedBy: adminUid,
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });
    batchSize += 1;

    for (const doc of conflictDocs) {
      batch.update(doc.ref, {
        status: "cancelled",
        cancelledAt: fieldValue.serverTimestamp(),
        cancelledBy: adminUid,
        cancelledByRole: "admin",
        cancelReason: "exam_started",
        updatedAt: fieldValue.serverTimestamp(),
      });
      batchSize += 1;

      if (batchSize >= 400) {
        await batch.commit();
        batch = db.batch();
        batchSize = 0;
      }
    }

    if (batchSize > 0) {
      await batch.commit();
    }

    await deleteWaitingZumreQueuesWhenClosed({}, now, {
      forceClosed: true,
    });
    const studyCloseResult = await closeActiveStudySessionsForInstitutionMode();

    return {
      ok: true,
      started: true,
      examId: targetId,
      examType,
      examEndsAt: scheduledEnd.toISOString(),
      cancelledCount: conflictDocs.length,
      closedStudySessions: studyCloseResult.closedCount,
    };
  }
);

exports.ensureStudySession = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const staff = await assertRoleCaller(request, "studyGuard");
    const now = new Date();
    const scheduleDoc = await db
      .collection("settings")
      .doc("zumreSchedule")
      .get();
    const runtimeDoc = await db
      .collection("settings")
      .doc("runtimeState")
      .get();

    if (!scheduleDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Etüt saatleri henüz tanımlanmamış."
      );
    }

    const scheduleData = scheduleDoc.data() || {};
    const runtimeState = buildEffectiveRuntimeState(
      scheduleData,
      runtimeDoc.data() || {},
      now
    );

    if (
      runtimeState.institutionMode !== "active" ||
      runtimeState.isStudyOpen !== true
    ) {
      throw new HttpsError(
        "failed-precondition",
        "Şu an etüt saati aktif değil."
      );
    }

    const slot = findCurrentStudySlot(scheduleData, now);
    if (!slot) {
      throw new HttpsError(
        "failed-precondition",
        "Aktif etüt saat aralığı bulunamadı."
      );
    }

    const sessionId = studySessionIdFor(staff.uid, slot);
    const sessionRef = db.collection("studySessions").doc(sessionId);

    await db.runTransaction(async (transaction) => {
      const existingDoc = await transaction.get(sessionRef);

      if (existingDoc.exists) {
        const existingData = existingDoc.data() || {};
        if (existingData.status === "active") {
          return;
        }

        throw new HttpsError(
          "failed-precondition",
          "Bu etüt saat aralığı daha önce kapatılmış."
        );
      }

      transaction.set(sessionRef, {
        staffId: staff.uid,
        staffName:
          staff.data.fullName ||
          staff.data.name ||
          staff.data.email ||
          "Etüt Görevlisi",
        staffRole: staff.data.role || "studyGuard",
        status: "active",
        startedAt: fieldValue.serverTimestamp(),
        endedAt: null,
        studentCount: 0,
        activeStudentCount: 0,
        slotKey: `${slot.dateKey}-${slot.start}-${slot.end}`,
        slotDate: slot.dateKey,
        slotStart: slot.start,
        slotEnd: slot.end,
        dutyTeacherId: null,
        dutyTeacherName: null,
        dutyTeacherPreviousStatus: null,
        createdAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });
    });

    return {
      ok: true,
      sessionId,
      slotText: `${slot.start} - ${slot.end}`,
    };
  }
);

exports.getAppointmentAvailability = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const student = await assertRoleCaller(request, "student");
    const subject = cleanText(request.data?.subject);
    const teacherIdFilter = cleanText(request.data?.teacherId);
    const dateKey = cleanText(request.data?.dateKey);
    const questionCount = normalizeQuestionCount(request.data?.questionCount);
    const estimatedMinutes = estimatedMinutesForQuestionCount(questionCount);
    const date = parseDateKeyToIstanbulNoon(dateKey);

    if (!subject) {
      throw new HttpsError("invalid-argument", "Lütfen bir ders seçin.");
    }

    if (!date) {
      throw new HttpsError("invalid-argument", "Geçerli bir tarih seçin.");
    }

    const [
      scheduleDoc,
      runtimeDoc,
      plannedExamDoc,
      studentAppointmentsSnapshot,
      teachersSnapshot,
      studyDutySnapshot,
    ] = await Promise.all([
      db.collection("settings").doc("zumreSchedule").get(),
      db.collection("settings").doc("runtimeState").get(),
      db.collection("settings").doc("plannedExam").get(),
      db.collection("appointments")
        .where("studentId", "==", student.uid)
        .where("dateKey", "==", dateKey)
        .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
        .orderBy("scheduledStart", "asc")
        .get(),
      db.collection("users")
        .where("role", "==", "teacher")
        .get(),
      db.collection("studySessions")
        .where("status", "==", "active")
        .get(),
    ]);

    const scheduleData = scheduleDoc.data() || {};
    const runtimeData = runtimeDoc.data() || {};
    const plannedExamData = plannedExamDoc.data() || {};
    if (
      resolveInstitutionMode(runtimeData, date).institutionMode === "closed"
    ) {
      return {
        ok: true,
        dateKey,
        teachers: [],
        message: "Kurum seçilen gün kapalı.",
      };
    }

    const dayParts = getIstanbulDateParts(date);
    const slots = getZumreSlots(scheduleData, dayParts.weekday);
    if (slots.length === 0) {
      return {
        ok: true,
        dateKey,
        teachers: [],
        message: "Seçilen gün için zümre saati bulunmuyor.",
      };
    }

    const teachers = teachersSnapshot.docs
      .filter((doc) => {
        if (teacherIdFilter && doc.id !== teacherIdFilter) return false;
        const data = doc.data();
        if (!teacherHasSubject(data, subject)) return false;
        if (data.manualAbsentDate === dateKey) return false;
        return true;
      })
      .slice(0, MAX_AVAILABILITY_TEACHERS);

    const resultTeachers = [];

    for (const teacherDoc of teachers) {
      const teacherData = teacherDoc.data();
      const teacherName = publicDisplayName(teacherData, "Öğretmen");

      const teacherAppointmentsSnapshot = await db.collection("appointments")
        .where("teacherId", "==", teacherDoc.id)
        .where("dateKey", "==", dateKey)
        .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
        .orderBy("scheduledStart", "asc")
        .get();

      const availableSlots = [];

      for (const slot of slots) {
        for (const option of generateAppointmentStartOptions({
          dateKey,
          slot,
          durationMinutes: estimatedMinutes,
          teacherAppointmentDocs: teacherAppointmentsSnapshot.docs,
          studentAppointmentDocs: studentAppointmentsSnapshot.docs,
        })) {
          const startDate = new Date(option.scheduledStart);
          const endDate = new Date(option.scheduledEnd);

          if (blockingReasonForAppointment({
            runtimeData,
            plannedExamData,
            startDate,
            endDate,
          })) {
            continue;
          }

          if (!teacherScheduledForAppointment(teacherData, startDate, endDate)) {
            continue;
          }

          const teacherDutyDocs = studyDutySnapshot.docs.filter(
            (doc) => doc.data().dutyTeacherId === teacherDoc.id
          );
          if (
            studyDutyConflictsWithAppointment(
              teacherDutyDocs,
              startDate,
              endDate
            )
          ) {
            continue;
          }

          availableSlots.push(option);
        }
      }

      if (availableSlots.length > 0) {
        resultTeachers.push({
          teacherId: teacherDoc.id,
          teacherName,
          slots: availableSlots.slice(0, 24),
        });
      }
    }

    return {
      ok: true,
      dateKey,
      questionCount,
      estimatedMinutes,
      teachers: resultTeachers,
    };
  }
);

exports.createAppointment = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const student = await assertRoleCaller(request, "student");
    const subject = cleanText(request.data?.subject);
    const teacherId = cleanText(request.data?.teacherId);
    const idempotencyKey = cleanIdempotencyKey(request.data?.idempotencyKey);
    const questionCount = normalizeQuestionCount(request.data?.questionCount);
    const estimatedMinutes = estimatedMinutesForQuestionCount(questionCount);
    const scheduledStart = parseRequestedAppointmentStart(
      request.data?.scheduledStart ?? request.data?.requestedStart
    );

    if (!subject) {
      throw new HttpsError("invalid-argument", "Lütfen bir ders seçin.");
    }

    if (!teacherId) {
      throw new HttpsError("invalid-argument", "Lütfen bir öğretmen seçin.");
    }

    if (!idempotencyKey) {
      throw new HttpsError(
        "invalid-argument",
        "Randevu güvenlik anahtarı eksik veya geçersiz."
      );
    }

    if (!scheduledStart) {
      throw new HttpsError("invalid-argument", "Geçerli bir saat seçin.");
    }

    const now = new Date();
    if (scheduledStart.getTime() <= now.getTime()) {
      throw new HttpsError(
        "failed-precondition",
        "Geçmiş bir saate planlı zümre oluşturulamaz."
      );
    }

    const startParts = getIstanbulDateParts(scheduledStart);

    const scheduledEnd = new Date(
      scheduledStart.getTime() + estimatedMinutes * 60 * 1000
    );
    const dateKey = startParts.dateKey;
    const appointmentId = appointmentIdFor(student.uid, idempotencyKey);
    const appointmentRef = db.collection("appointments").doc(appointmentId);
    const teacherLockRef = db.collection("appointmentLocks").doc(
      appointmentLockId("teacher", teacherId, dateKey)
    );
    const studentLockRef = db.collection("appointmentLocks").doc(
      appointmentLockId("student", student.uid, dateKey)
    );

    const result = await db.runTransaction(async (transaction) => {
      const [
        appointmentDoc,
        teacherLockDoc,
        studentLockDoc,
        scheduleDoc,
        runtimeDoc,
        plannedExamDoc,
        studentDoc,
        teacherDoc,
        teacherAppointmentsSnapshot,
        studentAppointmentsSnapshot,
        studyDutySnapshot,
      ] = await Promise.all([
        transaction.get(appointmentRef),
        transaction.get(teacherLockRef),
        transaction.get(studentLockRef),
        transaction.get(db.collection("settings").doc("zumreSchedule")),
        transaction.get(db.collection("settings").doc("runtimeState")),
        transaction.get(db.collection("settings").doc("plannedExam")),
        transaction.get(student.ref),
        transaction.get(db.collection("users").doc(teacherId)),
        transaction.get(
          db.collection("appointments")
            .where("teacherId", "==", teacherId)
            .where("dateKey", "==", dateKey)
            .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
            .orderBy("scheduledStart", "asc")
        ),
        transaction.get(
          db.collection("appointments")
            .where("studentId", "==", student.uid)
            .where("dateKey", "==", dateKey)
            .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
            .orderBy("scheduledStart", "asc")
        ),
        transaction.get(
          db.collection("studySessions")
            .where("status", "==", "active")
        ),
      ]);

      if (appointmentDoc.exists) {
        const data = appointmentDoc.data() || {};
        if (
          data.studentId !== student.uid ||
          data.idempotencyKey !== idempotencyKey
        ) {
          throw new HttpsError(
            "already-exists",
            "Bu randevu anahtarı kullanılamıyor."
          );
        }

        if (
          !appointmentMatchesBookingIdentity(data, {
            studentId: student.uid,
            teacherId,
            subject,
            questionCount,
            dateKey,
            scheduledStart,
          })
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Bu randevu anahtarı farklı bir planlı zümre için kullanılmış."
          );
        }

        return {
          appointmentId,
          teacherId: data.teacherId,
          teacherName: data.teacherName,
          scheduledStart: timestampToDate(data.scheduledStart)?.toISOString(),
          scheduledEnd: timestampToDate(data.scheduledEnd)?.toISOString(),
          idempotent: true,
        };
      }

      if (!studentDoc.exists || studentDoc.data()?.role !== "student") {
        throw new HttpsError(
          "permission-denied",
          "Bu işlem için öğrenci hesabı gerekir."
        );
      }

      if (!teacherDoc.exists || teacherDoc.data()?.role !== "teacher") {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen öğretmen bulunamadı."
        );
      }

      const studentData = studentDoc.data() || {};
      const teacherData = teacherDoc.data() || {};

      if (studentData.isInStudySession === true) {
        throw new HttpsError(
          "failed-precondition",
          "Etütteyken planlı zümre oluşturulamaz."
        );
      }

      if (!teacherHasSubject(teacherData, subject)) {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen öğretmen bu ders için uygun değil."
        );
      }

      if (teacherData.manualAbsentDate === dateKey) {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen öğretmen o gün kurumda değil görünüyor."
        );
      }

      const scheduleData = scheduleDoc.data() || {};
      const plannedExamData = plannedExamDoc.data() || {};
      const slot = findContainingZumreSlot(
        scheduleData,
        scheduledStart,
        scheduledEnd
      );

      if (!slot) {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen saat tanımlı zümre saatleri içinde değil."
        );
      }

      if (!teacherScheduledForAppointment(teacherData, scheduledStart, scheduledEnd)) {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen öğretmen bu saatte kurum programında uygun değil."
        );
      }

      const runtimeConflict = blockingReasonForAppointment({
        runtimeData: runtimeDoc.data() || {},
        plannedExamData,
        startDate: scheduledStart,
        endDate: scheduledEnd,
      });
      if (runtimeConflict) {
        throw new HttpsError("failed-precondition", runtimeConflict);
      }

      const teacherDutyDocs = studyDutySnapshot.docs.filter(
        (doc) => doc.data().dutyTeacherId === teacherId
      );
      if (
        studyDutyConflictsWithAppointment(
          teacherDutyDocs,
          scheduledStart,
          scheduledEnd
        )
      ) {
        throw new HttpsError(
          "failed-precondition",
          "Seçilen öğretmenin bu saatte etüt görevi bulunuyor."
        );
      }

      if (
        appointmentOverlapsDocs(
          teacherAppointmentsSnapshot.docs,
          scheduledStart,
          scheduledEnd
        )
      ) {
        throw new HttpsError(
          "already-exists",
          "Seçilen öğretmenin bu saatte başka planlı zümresi var."
        );
      }

      if (
        appointmentOverlapsDocs(
          studentAppointmentsSnapshot.docs,
          scheduledStart,
          scheduledEnd,
          { bufferMinutes: APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES }
        )
      ) {
        throw new HttpsError(
          "already-exists",
          "Bu saatte başka bir planlı zümreniz bulunuyor."
        );
      }

      const slotKey = buildSlotKey(dateKey, slot);
      const plannedCapacity = plannedCapacityMinutesForSlot(slot);
      const usedCapacity = appointmentMinutesInSlot(
        teacherAppointmentsSnapshot.docs,
        slotKey
      );

      if (usedCapacity + estimatedMinutes > plannedCapacity) {
        throw new HttpsError(
          "resource-exhausted",
          "Bu öğretmenin planlı zümre kapasitesi dolu."
        );
      }

      const teacherName = publicDisplayName(teacherData, "Öğretmen");
      const studentName = publicDisplayName(studentData, "Öğrenci");

      transaction.set(appointmentRef, {
        studentId: student.uid,
        studentName,
        teacherId,
        teacherName,
        subject,
        questionCount,
        estimatedMinutes,
        dateKey,
        slotKey,
        scheduledStart: timestampFromDate(scheduledStart),
        scheduledEnd: timestampFromDate(scheduledEnd),
        status: APPOINTMENT_STATUS_SCHEDULED,
        idempotencyKey,
        createdAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      transaction.set(teacherLockRef, {
        scope: "teacher",
        ownerId: teacherId,
        dateKey,
        lastAppointmentId: appointmentId,
        updatedAt: fieldValue.serverTimestamp(),
        revision: teacherLockDoc.exists
          ? fieldValue.increment(1)
          : 1,
      }, { merge: true });

      transaction.set(studentLockRef, {
        scope: "student",
        ownerId: student.uid,
        dateKey,
        lastAppointmentId: appointmentId,
        updatedAt: fieldValue.serverTimestamp(),
        revision: studentLockDoc.exists
          ? fieldValue.increment(1)
          : 1,
      }, { merge: true });

      return {
        appointmentId,
        teacherId,
        teacherName,
        scheduledStart: scheduledStart.toISOString(),
        scheduledEnd: scheduledEnd.toISOString(),
        idempotent: false,
      };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.routeQueueRequest = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const startedAt = Date.now();
    const student = await assertRoleCaller(request, "student");
    const subject = cleanText(request.data?.subject);
    const requestedTeacherId = cleanText(request.data?.teacherId);
    const questionCount = normalizeQuestionCount(request.data?.questionCount);
    const estimatedMinutes = estimatedMinutesForQuestionCount(questionCount);

    if (!subject) {
      throw new HttpsError(
        "invalid-argument",
        "Lütfen bir ders seçin."
      );
    }

    const scheduleRef = db.collection("settings").doc("zumreSchedule");
    const runtimeRef = db.collection("settings").doc("runtimeState");

    const result = await db.runTransaction(async (transaction) => {
      const [
        scheduleDoc,
        runtimeDoc,
        studentDoc,
        activeQueuesSnapshot,
        teachersSnapshot,
      ] = await Promise.all([
        transaction.get(scheduleRef),
        transaction.get(runtimeRef),
        transaction.get(student.ref),
        transaction.get(
          db.collection("queues")
            .where("status", "in", ["waiting", "in_progress"])
        ),
        transaction.get(
          db.collection("users")
            .where("role", "==", "teacher")
            .where("teacherStatus", "==", "available")
        ),
      ]);

      assertQueueRuntimeOpen(
        scheduleDoc.data() || {},
        runtimeDoc.data() || {},
        new Date()
      );

      if (!studentDoc.exists || studentDoc.data()?.role !== "student") {
        throw new HttpsError(
          "permission-denied",
          "Bu işlem için yetkiniz yok."
        );
      }

      const studentData = studentDoc.data() || {};

      if (studentData.isInStudySession === true) {
        throw new HttpsError(
          "failed-precondition",
          "Etütteyken zümre sırası alınamaz."
        );
      }

      const existingQueue = activeQueuesSnapshot.docs.find(
        (doc) => doc.data().studentId === student.uid
      );

      if (existingQueue) {
        throw new HttpsError(
          "already-exists",
          "Zaten aktif bir sıranız var."
        );
      }

      const candidateTeachers = teachersSnapshot.docs.filter(
        (doc) => teacherHasSubject(doc.data(), subject)
      );

      if (candidateTeachers.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          "Bu ders için şu anda müsait öğretmen bulunamadı."
        );
      }

      const selected = requestedTeacherId
        ? {
            teacher: candidateTeachers.find(
              (doc) => doc.id === requestedTeacherId
            ),
          }
        : selectBestTeacher(
          candidateTeachers,
          activeQueuesSnapshot.docs,
          questionCount
        );

      if (!selected || !selected.teacher) {
        throw new HttpsError(
          "failed-precondition",
          requestedTeacherId
            ? "Seçilen öğretmen şu anda bu ders için müsait değil."
            : "Bu ders için şu anda müsait öğretmen bulunamadı."
        );
      }

      const teacherData = selected.teacher.data();
      const teacherName =
        teacherData.fullName ||
        teacherData.name ||
        teacherData.email ||
        "Öğretmen";
      const queueRef = db.collection("queues").doc();

      transaction.set(queueRef, {
        teacherName,
        studentId: student.uid,
        teacherId: selected.teacher.id,
        subject,
        status: "waiting",
        studentName:
          studentData.fullName ||
          studentData.name ||
          studentData.username ||
          "Öğrenci",
        questionCount,
        estimatedMinutes,
        extraMinutes: 0,
        createdAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
        routedBy: requestedTeacherId ? "student_selected_teacher" : "server",
      });

      transaction.update(student.ref, {
        lastQueueRequestAt: fieldValue.serverTimestamp(),
      });
      transaction.update(selected.teacher.ref, {
        lastQueueRoutedAt: fieldValue.serverTimestamp(),
      });

      return {
        queueId: queueRef.id,
        teacherId: selected.teacher.id,
        teacherName,
        candidateCount: candidateTeachers.length,
        activeQueueCount: activeQueuesSnapshot.size,
      };
    });

    console.log("routeQueueRequest", {
      uid: student.uid,
      subject,
      questionCount,
      requestedTeacherId: requestedTeacherId || null,
      queueId: result.queueId,
      teacherId: result.teacherId,
      candidateCount: result.candidateCount,
      activeQueueCount: result.activeQueueCount,
      totalMs: Date.now() - startedAt,
    });

    return {
      ok: true,
      queueId: result.queueId,
      teacherId: result.teacherId,
      teacherName: result.teacherName,
    };
  }
);

exports.routeQueueTransfer = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const startedAt = Date.now();
    const teacher = await assertRoleCaller(request, "teacher");
    const queueId = cleanText(request.data?.queueId);

    if (!queueId) {
      throw new HttpsError(
        "invalid-argument",
        "Geçersiz sıra bilgisi."
      );
    }

    const queueRef = db.collection("queues").doc(queueId);

    const result = await db.runTransaction(async (transaction) => {
      const [queueDoc, activeQueuesSnapshot, teachersSnapshot] =
        await Promise.all([
          transaction.get(queueRef),
          transaction.get(
            db.collection("queues")
              .where("status", "in", ["waiting", "in_progress"])
          ),
          transaction.get(
            db.collection("users")
              .where("role", "==", "teacher")
              .where("teacherStatus", "==", "available")
          ),
        ]);

      if (!queueDoc.exists) {
        throw new HttpsError(
          "not-found",
          "Sıra kaydı bulunamadı."
        );
      }

      const queueData = queueDoc.data() || {};
      const status = queueData.status;

      if (queueData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu sırayı devretme yetkiniz yok."
        );
      }

      if (status !== "waiting" && status !== "in_progress") {
        throw new HttpsError(
          "failed-precondition",
          "Yalnızca aktif veya bekleyen sorular devredilebilir."
        );
      }

      const subject = cleanText(queueData.subject);
      const questionCount = normalizeQuestionCount(queueData.questionCount);
      const candidateTeachers = teachersSnapshot.docs.filter(
        (doc) =>
          doc.id !== teacher.uid &&
          teacherHasSubject(doc.data(), subject)
      );

      if (candidateTeachers.length === 0) {
        throw new HttpsError(
          "failed-precondition",
          `${subject} branşında devredilebilecek müsait öğretmen bulunamadı.`
        );
      }

      const selected = selectBestTeacher(
        candidateTeachers,
        activeQueuesSnapshot.docs.filter((doc) => doc.id !== queueDoc.id),
        questionCount
      );

      if (!selected) {
        throw new HttpsError(
          "failed-precondition",
          `${subject} branşında devredilebilecek müsait öğretmen bulunamadı.`
        );
      }

      const selectedData = selected.teacher.data();
      const selectedTeacherName =
        selectedData.fullName ||
        selectedData.name ||
        selectedData.email ||
        "Öğretmen";

      transaction.update(queueRef, {
        teacherId: selected.teacher.id,
        teacherName: selectedTeacherName,
        status: "waiting",
        transferredAt: fieldValue.serverTimestamp(),
        transferredFromTeacherId: teacher.uid,
        transferredFromTeacherName:
          teacher.data.fullName ||
          teacher.data.name ||
          teacher.data.email ||
          "Öğretmen",
        updatedAt: fieldValue.serverTimestamp(),
      });
      transaction.update(selected.teacher.ref, {
        lastQueueRoutedAt: fieldValue.serverTimestamp(),
      });

      return {
        teacherId: selected.teacher.id,
        teacherName: selectedTeacherName,
        subject,
        candidateCount: candidateTeachers.length,
        activeQueueCount: activeQueuesSnapshot.size,
      };
    });

    console.log("routeQueueTransfer", {
      uid: teacher.uid,
      queueId,
      subject: result.subject,
      teacherId: result.teacherId,
      candidateCount: result.candidateCount,
      activeQueueCount: result.activeQueueCount,
      totalMs: Date.now() - startedAt,
    });

    return {
      ok: true,
      teacherId: result.teacherId,
      teacherName: result.teacherName,
    };
  }
);

exports.teacherTakeNextQueue = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");

    const nextQueueId = await db.runTransaction((transaction) =>
      startNextWaitingQueueInTransaction(transaction, teacher.uid)
    );

    return {
      ok: true,
      startedQueueId: nextQueueId,
    };
  }
);

exports.teacherStartAppointment = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const appointmentId = cleanText(request.data?.appointmentId);

    if (!appointmentId) {
      throw new HttpsError("invalid-argument", "Geçersiz planlı zümre bilgisi.");
    }

    const appointmentRef = db.collection("appointments").doc(appointmentId);
    const queueRef = db.collection("queues").doc(
      appointmentLinkedQueueId(appointmentId)
    );

    const result = await db.runTransaction(async (transaction) => {
      const [
        appointmentDoc,
        linkedQueueDoc,
        teacherActiveSnapshot,
      ] = await Promise.all([
        transaction.get(appointmentRef),
        transaction.get(queueRef),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "in_progress")
            .limit(1)
        ),
      ]);

      if (!appointmentDoc.exists) {
        throw new HttpsError("not-found", "Planlı zümre bulunamadı.");
      }

      const appointmentData = appointmentDoc.data() || {};

      if (appointmentData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu planlı zümreyi başlatma yetkiniz yok."
        );
      }

      if (appointmentData.status === "started" && appointmentData.linkedQueueId) {
        return {
          started: false,
          linkedQueueId: appointmentData.linkedQueueId,
          idempotent: true,
        };
      }

      if (appointmentData.status !== APPOINTMENT_STATUS_SCHEDULED) {
        throw new HttpsError(
          "failed-precondition",
          "Bu planlı zümre artık başlatılabilir durumda değil."
        );
      }

      const dueState = appointmentCanBecomeLive(appointmentData);
      if (!dueState.ok) {
        throw new HttpsError("failed-precondition", dueState.reason);
      }

      if (!teacherActiveSnapshot.empty) {
        throw new HttpsError(
          "failed-precondition",
          "Önce devam eden öğrenci işlemini tamamlayın."
        );
      }

      const studentActiveSnapshot = await transaction.get(
        db.collection("queues")
          .where("studentId", "==", appointmentData.studentId)
          .where("status", "in", ["waiting", "in_progress"])
          .limit(1)
      );

      if (!studentActiveSnapshot.empty) {
        throw new HttpsError(
          "failed-precondition",
          "Öğrencinin şu anda aktif bir zümre sırası var."
        );
      }

      if (linkedQueueDoc.exists) {
        transaction.update(appointmentRef, {
          status: "started",
          startedAt: fieldValue.serverTimestamp(),
          linkedQueueId: queueRef.id,
          updatedAt: fieldValue.serverTimestamp(),
        });

        return {
          started: true,
          linkedQueueId: queueRef.id,
          idempotent: true,
        };
      }

      const now = new Date();
      transaction.set(
        queueRef,
        buildAppointmentLinkedQueueData(appointmentId, appointmentData, now)
      );
      transaction.update(appointmentRef, {
        status: "started",
        startedAt: fieldValue.serverTimestamp(),
        linkedQueueId: queueRef.id,
        updatedAt: fieldValue.serverTimestamp(),
      });

      return {
        started: true,
        linkedQueueId: queueRef.id,
        idempotent: false,
      };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.teacherNoShowAppointment = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const appointmentId = cleanText(request.data?.appointmentId);

    if (!appointmentId) {
      throw new HttpsError("invalid-argument", "Geçersiz planlı zümre bilgisi.");
    }

    const appointmentRef = db.collection("appointments").doc(appointmentId);

    const result = await db.runTransaction(async (transaction) => {
      const appointmentDoc = await transaction.get(appointmentRef);

      if (!appointmentDoc.exists) {
        throw new HttpsError("not-found", "Planlı zümre bulunamadı.");
      }

      const appointmentData = appointmentDoc.data() || {};

      if (appointmentData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu planlı zümre için işlem yetkiniz yok."
        );
      }

      if (appointmentData.status !== APPOINTMENT_STATUS_SCHEDULED) {
        throw new HttpsError(
          "failed-precondition",
          "Bu planlı zümre için gelmedi işlemi yapılamaz."
        );
      }

      const dueState = appointmentCanBecomeLive(appointmentData);
      if (!dueState.ok) {
        throw new HttpsError("failed-precondition", dueState.reason);
      }

      transaction.update(appointmentRef, {
        status: "no_show",
        noShowAt: fieldValue.serverTimestamp(),
        noShowVerificationStatus: NO_SHOW_VERIFICATION_PENDING,
        noShowVerifiedAt: null,
        noShowVerificationReason: null,
        noShowVerificationCheckedAt: null,
        updatedAt: fieldValue.serverTimestamp(),
      });

      return { noShow: true };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.getAppointmentTransferOptions = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const appointmentId = cleanText(request.data?.appointmentId);

    if (!appointmentId) {
      throw new HttpsError("invalid-argument", "Geçersiz planlı zümre bilgisi.");
    }

    const appointmentDoc = await db.collection("appointments").doc(appointmentId).get();
    if (!appointmentDoc.exists) {
      throw new HttpsError("not-found", "Planlı zümre bulunamadı.");
    }

    const appointmentData = appointmentDoc.data() || {};
    const now = new Date();
    if (!canRequesterTransferAppointment(appointmentData, teacher, now)) {
      throw new HttpsError(
        "permission-denied",
        "Bu planlı zümreyi devretme yetkiniz yok."
      );
    }

    const futureState = appointmentIsFutureScheduled(appointmentData, now);
    if (!futureState.ok) {
      throw new HttpsError("failed-precondition", futureState.reason);
    }

    const dateKey = cleanText(appointmentData.dateKey);
    const [
      scheduleDoc,
      runtimeDoc,
      plannedExamDoc,
      teachersSnapshot,
      dateAppointmentsSnapshot,
      studyDutySnapshot,
    ] = await Promise.all([
      db.collection("settings").doc("zumreSchedule").get(),
      db.collection("settings").doc("runtimeState").get(),
      db.collection("settings").doc("plannedExam").get(),
      db.collection("users").where("role", "==", "teacher").get(),
      db.collection("appointments")
        .where("dateKey", "==", dateKey)
        .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
        .get(),
      db.collection("studySessions")
        .where("status", "==", "active")
        .get(),
    ]);

    const scheduleData = scheduleDoc.data() || {};
    const runtimeData = runtimeDoc.data() || {};
    const plannedExamData = plannedExamDoc.data() || {};
    const options = [];

    for (const teacherDoc of teachersSnapshot.docs) {
      if (teacherDoc.id === appointmentData.teacherId) continue;

      const eligibility = appointmentTransferEligibility({
        appointmentId,
        appointmentData,
        destinationTeacherDoc: teacherDoc,
        dateAppointmentDocs: dateAppointmentsSnapshot.docs,
        studyDutyDocs: studyDutySnapshot.docs,
        scheduleData,
        runtimeData,
        plannedExamData,
      });

      if (!eligibility.ok) continue;

      options.push({
        teacherId: teacherDoc.id,
        teacherName: eligibility.teacherName,
        plannedLoad: eligibility.plannedLoad,
      });
    }

    options.sort((a, b) => {
      if (a.plannedLoad !== b.plannedLoad) return a.plannedLoad - b.plannedLoad;
      return a.teacherName.localeCompare(b.teacherName, "tr");
    });

    const selfEligibility = appointmentData.teacherId !== teacher.uid
      ? appointmentTransferEligibility({
        appointmentId,
        appointmentData,
        destinationTeacherDoc: teachersSnapshot.docs.find((doc) => doc.id === teacher.uid),
        dateAppointmentDocs: dateAppointmentsSnapshot.docs,
        studyDutyDocs: studyDutySnapshot.docs,
        scheduleData,
        runtimeData,
        plannedExamData,
      })
      : { ok: false };

    return {
      ok: true,
      teachers: options.slice(0, MAX_AVAILABILITY_TEACHERS),
      canReturnToSelf: selfEligibility.ok === true,
    };
  }
);

exports.transferAppointment = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const appointmentId = cleanText(request.data?.appointmentId);
    const mode = cleanText(request.data?.mode || "manual");
    const requestedTeacherId = cleanText(request.data?.teacherId);

    if (!appointmentId) {
      throw new HttpsError("invalid-argument", "Geçersiz planlı zümre bilgisi.");
    }

    if (mode !== "auto" && mode !== "manual" && mode !== "self") {
      throw new HttpsError("invalid-argument", "Geçersiz devretme türü.");
    }

    const appointmentRef = db.collection("appointments").doc(appointmentId);

    const result = await db.runTransaction(async (transaction) => {
      const appointmentDoc = await transaction.get(appointmentRef);

      if (!appointmentDoc.exists) {
        throw new HttpsError("not-found", "Planlı zümre bulunamadı.");
      }

      const appointmentData = appointmentDoc.data() || {};
      const now = new Date();

      if (!canRequesterTransferAppointment(appointmentData, teacher, now)) {
        throw new HttpsError(
          "permission-denied",
          "Bu planlı zümreyi devretme yetkiniz yok."
        );
      }

      const futureState = appointmentIsFutureScheduled(appointmentData, now);
      if (!futureState.ok) {
        throw new HttpsError("failed-precondition", futureState.reason);
      }

      const dateKey = cleanText(appointmentData.dateKey);
      const [
        scheduleDoc,
        runtimeDoc,
        plannedExamDoc,
        teachersSnapshot,
        dateAppointmentsSnapshot,
        studyDutySnapshot,
      ] = await Promise.all([
        transaction.get(db.collection("settings").doc("zumreSchedule")),
        transaction.get(db.collection("settings").doc("runtimeState")),
        transaction.get(db.collection("settings").doc("plannedExam")),
        transaction.get(db.collection("users").where("role", "==", "teacher")),
        transaction.get(
          db.collection("appointments")
            .where("dateKey", "==", dateKey)
            .where("status", "in", ACTIVE_APPOINTMENT_STATUSES)
        ),
        transaction.get(
          db.collection("studySessions")
            .where("status", "==", "active")
        ),
      ]);

      let destinationTeacherDoc = null;
      let destinationEligibility = null;
      const plannedExamData = plannedExamDoc.data() || {};

      if (mode === "manual") {
        if (!requestedTeacherId) {
          throw new HttpsError("invalid-argument", "Lütfen öğretmen seçin.");
        }

        if (requestedTeacherId === appointmentData.teacherId) {
          throw new HttpsError(
            "failed-precondition",
            "Planlı zümre zaten bu öğretmende."
          );
        }

        destinationTeacherDoc = teachersSnapshot.docs.find(
          (doc) => doc.id === requestedTeacherId
        );
        destinationEligibility = appointmentTransferEligibility({
          appointmentId,
          appointmentData,
          destinationTeacherDoc,
          dateAppointmentDocs: dateAppointmentsSnapshot.docs,
          studyDutyDocs: studyDutySnapshot.docs,
          scheduleData: scheduleDoc.data() || {},
          runtimeData: runtimeDoc.data() || {},
          plannedExamData,
        });
      } else if (mode === "self") {
        destinationTeacherDoc = teachersSnapshot.docs.find(
          (doc) => doc.id === teacher.uid
        );
        destinationEligibility = appointmentTransferEligibility({
          appointmentId,
          appointmentData,
          destinationTeacherDoc,
          dateAppointmentDocs: dateAppointmentsSnapshot.docs,
          studyDutyDocs: studyDutySnapshot.docs,
          scheduleData: scheduleDoc.data() || {},
          runtimeData: runtimeDoc.data() || {},
          plannedExamData,
        });
      } else {
        const candidates = [];
        for (const teacherDoc of teachersSnapshot.docs) {
          if (teacherDoc.id === appointmentData.teacherId) continue;

          const eligibility = appointmentTransferEligibility({
            appointmentId,
            appointmentData,
            destinationTeacherDoc: teacherDoc,
            dateAppointmentDocs: dateAppointmentsSnapshot.docs,
            studyDutyDocs: studyDutySnapshot.docs,
            scheduleData: scheduleDoc.data() || {},
            runtimeData: runtimeDoc.data() || {},
            plannedExamData,
          });

          if (eligibility.ok) {
            candidates.push({ teacherDoc, eligibility });
          }
        }

        candidates.sort((a, b) => {
          if (a.eligibility.plannedLoad !== b.eligibility.plannedLoad) {
            return a.eligibility.plannedLoad - b.eligibility.plannedLoad;
          }
          return Math.random() < 0.5 ? -1 : 1;
        });

        if (candidates.length > 0) {
          destinationTeacherDoc = candidates[0].teacherDoc;
          destinationEligibility = candidates[0].eligibility;
        }
      }

      if (!destinationEligibility?.ok || !destinationTeacherDoc) {
        throw new HttpsError(
          "failed-precondition",
          destinationEligibility?.reason || "Uygun öğretmen bulunamadı."
        );
      }

      const destinationTeacherId = destinationTeacherDoc.id;
      if (destinationTeacherId === appointmentData.teacherId) {
        throw new HttpsError(
          "failed-precondition",
          "Planlı zümre zaten bu öğretmende."
        );
      }

      const destinationLockRef = db.collection("appointmentLocks").doc(
        appointmentLockId("teacher", destinationTeacherId, dateKey)
      );
      const destinationLockDoc = await transaction.get(destinationLockRef);
      const editUntil = transferEditUntilFor(appointmentData, now);
      const fromTeacherName = cleanText(appointmentData.teacherName) || "Öğretmen";
      const toTeacherName = destinationEligibility.teacherName;

      transaction.update(appointmentRef, {
        teacherId: destinationTeacherId,
        teacherName: toTeacherName,
        transferredAt: fieldValue.serverTimestamp(),
        transferredFromTeacherId: teacher.uid,
        transferredFromTeacherName: fromTeacherName,
        transferToTeacherId: destinationTeacherId,
        transferToTeacherName: toTeacherName,
        transferEditUntil: timestampFromDate(editUntil),
        updatedAt: fieldValue.serverTimestamp(),
      });

      transaction.set(destinationLockRef, {
        scope: "teacher",
        ownerId: destinationTeacherId,
        dateKey,
        lastAppointmentId: appointmentId,
        updatedAt: fieldValue.serverTimestamp(),
        revision: destinationLockDoc.exists
          ? fieldValue.increment(1)
          : 1,
      }, { merge: true });

      return {
        transferred: true,
        teacherId: destinationTeacherId,
        teacherName: toTeacherName,
        transferEditUntil: editUntil.toISOString(),
      };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.cancelAppointment = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const user = await assertAuthenticatedUser(request);
    const appointmentId = cleanText(request.data?.appointmentId);

    if (!appointmentId) {
      throw new HttpsError("invalid-argument", "Geçersiz planlı zümre bilgisi.");
    }

    const appointmentRef = db.collection("appointments").doc(appointmentId);

    const result = await db.runTransaction(async (transaction) => {
      const appointmentDoc = await transaction.get(appointmentRef);

      if (!appointmentDoc.exists) {
        throw new HttpsError("not-found", "Planlı zümre bulunamadı.");
      }

      const appointmentData = appointmentDoc.data() || {};
      const futureState = appointmentIsFutureScheduled(appointmentData);
      if (!futureState.ok) {
        throw new HttpsError("failed-precondition", futureState.reason);
      }

      const role = user.data.role;
      const canCancel = appointmentData.studentId === user.uid ||
        appointmentData.teacherId === user.uid ||
        role === "admin";

      if (!canCancel) {
        throw new HttpsError(
          "permission-denied",
          "Bu planlı zümreyi iptal etme yetkiniz yok."
        );
      }

      transaction.update(appointmentRef, {
        status: "cancelled",
        cancelledAt: fieldValue.serverTimestamp(),
        cancelledBy: user.uid,
        cancelledByRole: role,
        updatedAt: fieldValue.serverTimestamp(),
      });

      return { cancelled: true };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.teacherStartQueue = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const queueId = cleanText(request.data?.queueId);
    const confirmedActiveQueueId = cleanText(
      request.data?.confirmedActiveQueueId
    );

    if (!queueId) {
      throw new HttpsError("invalid-argument", "Geçersiz sıra bilgisi.");
    }

    const queueRef = db.collection("queues").doc(queueId);

    const result = await db.runTransaction(async (transaction) => {
      const [queueDoc, activeSnapshot] = await Promise.all([
        transaction.get(queueRef),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "in_progress")
            .limit(1)
        ),
      ]);

      if (!queueDoc.exists) {
        throw new HttpsError("not-found", "Sıra kaydı bulunamadı.");
      }

      const queueData = queueDoc.data() || {};
      if (queueData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu sırayı başlatma yetkiniz yok."
        );
      }

      if (queueData.status === "in_progress") {
        return { started: false, completedCurrent: false };
      }

      if (queueData.status !== "waiting") {
        throw new HttpsError(
          "failed-precondition",
          "Bu sıra artık başlatılabilir durumda değil."
        );
      }

      let completedCurrent = false;
      if (!activeSnapshot.empty) {
        const activeDoc = activeSnapshot.docs[0];
        if (activeDoc.id === queueId) {
          return { started: false, completedCurrent: false };
        }

        if (activeDoc.id !== confirmedActiveQueueId) {
          throw new HttpsError(
            "failed-precondition",
            "Aktif soru değişti. Lütfen tekrar deneyin."
          );
        }

        transaction.update(activeDoc.ref, {
          status: "completed",
          completedAt: fieldValue.serverTimestamp(),
          updatedAt: fieldValue.serverTimestamp(),
        });
        completedCurrent = true;
      }

      transaction.update(queueRef, {
        status: "in_progress",
        startedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      return { started: true, completedCurrent };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.teacherCompleteQueue = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const queueId = cleanText(request.data?.queueId);

    if (!queueId) {
      throw new HttpsError("invalid-argument", "Geçersiz sıra bilgisi.");
    }

    const queueRef = db.collection("queues").doc(queueId);

    const result = await db.runTransaction(async (transaction) => {
      const [queueDoc, activeSnapshot, waitingSnapshot] = await Promise.all([
        transaction.get(queueRef),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "in_progress")
        ),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "waiting")
        ),
      ]);

      if (!queueDoc.exists) {
        throw new HttpsError("not-found", "Sıra kaydı bulunamadı.");
      }

      const queueData = queueDoc.data() || {};
      if (queueData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu sırayı tamamlama yetkiniz yok."
        );
      }

      if (queueData.status !== "in_progress") {
        return { completed: false, startedNextQueueId: null };
      }

      const otherActiveQueues = activeSnapshot.docs
        .filter((doc) => doc.id !== queueId);
      const nextQueue = selectNextWaitingQueueDoc(
        waitingSnapshot.docs,
        queueId
      );
      let appointmentRef = null;
      let appointmentDoc = null;

      if (queueData.source === "appointment" && queueData.appointmentId) {
        appointmentRef = db.collection("appointments").doc(
          cleanText(queueData.appointmentId)
        );
        appointmentDoc = await transaction.get(appointmentRef);

        if (!appointmentDoc.exists) {
          throw new HttpsError(
            "failed-precondition",
            "Bağlı planlı zümre kaydı bulunamadı."
          );
        }

        const appointmentData = appointmentDoc.data() || {};
        if (
          appointmentData.teacherId !== teacher.uid ||
          appointmentData.linkedQueueId !== queueId ||
          appointmentData.status !== "started"
        ) {
          throw new HttpsError(
            "failed-precondition",
            "Bağlı planlı zümre durumu geçerli değil."
          );
        }
      }

      transaction.update(queueRef, {
        status: "completed",
        completedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      if (appointmentRef) {
        transaction.update(appointmentRef, {
          status: "completed",
          completedAt: fieldValue.serverTimestamp(),
          updatedAt: fieldValue.serverTimestamp(),
        });
      }

      if (otherActiveQueues.length > 0) {
        return { completed: true, startedNextQueueId: null };
      }

      if (!nextQueue) {
        return { completed: true, startedNextQueueId: null };
      }

      transaction.update(nextQueue.ref, {
        status: "in_progress",
        startedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      return { completed: true, startedNextQueueId: nextQueue.id };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.teacherAddExtraMinutes = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const queueId = cleanText(request.data?.queueId);
    const minutes = Number(request.data?.minutes || 0);

    if (!queueId || ![1, 3].includes(minutes)) {
      throw new HttpsError("invalid-argument", "Geçersiz süre bilgisi.");
    }

    const queueRef = db.collection("queues").doc(queueId);

    const result = await db.runTransaction(async (transaction) => {
      const queueDoc = await transaction.get(queueRef);

      if (!queueDoc.exists) {
        throw new HttpsError("not-found", "Sıra kaydı bulunamadı.");
      }

      const queueData = queueDoc.data() || {};
      if (queueData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu sıraya süre ekleme yetkiniz yok."
        );
      }

      if (queueData.status !== "in_progress") {
        return { updated: false, status: cleanText(queueData.status) };
      }

      const currentExtra = Number(queueData.extraMinutes || 0);
      transaction.update(queueRef, {
        extraMinutes: currentExtra + minutes,
        updatedAt: fieldValue.serverTimestamp(),
      });

      return {
        updated: true,
        extraMinutes: currentExtra + minutes,
      };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

exports.teacherCancelQueue = onCall(
  {
    region: REGION,
  },
  async (request) => {
    const teacher = await assertRoleCaller(request, "teacher");
    const queueId = cleanText(request.data?.queueId);

    if (!queueId) {
      throw new HttpsError("invalid-argument", "Geçersiz sıra bilgisi.");
    }

    const queueRef = db.collection("queues").doc(queueId);

    const result = await db.runTransaction(async (transaction) => {
      const [queueDoc, activeSnapshot, waitingSnapshot] = await Promise.all([
        transaction.get(queueRef),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "in_progress")
        ),
        transaction.get(
          db.collection("queues")
            .where("teacherId", "==", teacher.uid)
            .where("status", "==", "waiting")
        ),
      ]);

      if (!queueDoc.exists) {
        throw new HttpsError("not-found", "Sıra kaydı bulunamadı.");
      }

      const queueData = queueDoc.data() || {};
      if (queueData.teacherId !== teacher.uid) {
        throw new HttpsError(
          "permission-denied",
          "Bu sırayı iptal etme yetkiniz yok."
        );
      }

      const status = queueData.status;
      if (status !== "waiting" && status !== "in_progress") {
        return { cancelled: false, startedNextQueueId: null };
      }

      transaction.update(queueRef, {
        status: "cancelled",
        cancelledAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      if (status !== "in_progress") {
        return { cancelled: true, startedNextQueueId: null };
      }

      const otherActiveQueues = activeSnapshot.docs
        .filter((doc) => doc.id !== queueId);
      const nextQueue = selectNextWaitingQueueDoc(
        waitingSnapshot.docs,
        queueId
      );

      if (otherActiveQueues.length > 0) {
        return { cancelled: true, startedNextQueueId: null };
      }

      if (!nextQueue) {
        return { cancelled: true, startedNextQueueId: null };
      }

      transaction.update(nextQueue.ref, {
        status: "in_progress",
        startedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

      return { cancelled: true, startedNextQueueId: nextQueue.id };
    });

    return {
      ok: true,
      ...result,
    };
  }
);

// ============================================================
// ETÜT OTURUMU KAPATMA
// ============================================================

async function claimStudySession(sessionRef) {
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(sessionRef);

    if (!snapshot.exists) {
      return null;
    }

    const data = snapshot.data();

    if (data.status !== "active") {
      return null;
    }

    /*
     * Aynı dakika iki scheduler çalışırsa yalnızca biri
     * oturumu kapatma hakkını alabilsin.
     */
    transaction.update(sessionRef, {
      status: "closing",
      closingStartedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    });

    return data;
  });
}

async function restoreSessionAfterFailure(sessionRef, error) {
  try {
    await sessionRef.update({
      status: "active",
      closingStartedAt: fieldValue.delete(),
      lastCloseError: String(error?.message || error),
      updatedAt: fieldValue.serverTimestamp(),
    });
  } catch (restoreError) {
    console.error(
      `Oturum tekrar active yapılamadı: ${sessionRef.id}`,
      restoreError
    );
  }
}

async function closeStudySession(sessionDoc) {
  const sessionRef = sessionDoc.ref;

  const claimedSessionData = await claimStudySession(sessionRef);

  /*
   * Başka bir scheduler bu oturumu kapatıyorsa veya oturum
   * daha önce tamamlandıysa işlem yapma.
   */
  if (!claimedSessionData) {
    return false;
  }

  try {
    const studentsSnapshot = await sessionRef
      .collection("students")
      .get();

    const batch = db.batch();

    /*
     * Öğrencilerin aktif etüt bilgisini temizle.
     * Geçmiş katılım kayıtlarını alt koleksiyonda koru.
     */
    for (const studentDoc of studentsSnapshot.docs) {
      const studentData = studentDoc.data();
      const studentId =
        studentData.studentId || studentDoc.id;

      if (!studentId) {
        continue;
      }

      const userRef = db.collection("users").doc(studentId);
      const userSnapshot = await userRef.get();

      /*
       * Öğrenci başka/yeni bir etüt oturumuna geçmişse
       * yeni oturum bilgisini yanlışlıkla temizleme.
       */
      if (
        userSnapshot.exists &&
        userSnapshot.data()?.activeStudySessionId === sessionRef.id
      ) {
        batch.update(userRef, {
          isInStudySession: false,
          activeStudySessionId: null,
        });
      }

      /*
       * Erken ayrılanların status değeri "left" olarak kalır.
       * Etüt sonuna kadar kalanlar completed yapılır.
       */
      if (studentData.status === "present") {
        batch.update(studentDoc.ref, {
          status: "completed",
          checkedOutAt: fieldValue.serverTimestamp(),
        });
      }
    }

    /*
     * Seçilmiş branş öğretmenini güncel günlük lifecycle'a göre döndür.
     */
    const dutyTeacherId = claimedSessionData.dutyTeacherId;

    if (dutyTeacherId) {
      const teacherRef = db
        .collection("users")
        .doc(dutyTeacherId);
      const teacherSnapshot = await teacherRef.get();
      const teacherData = teacherSnapshot.data() || {};

      const previousStatus =
        claimedSessionData.dutyTeacherPreviousStatus ||
        "available";
      const resolvedStatus = teacherSnapshot.exists
        ? resolveTeacherLifecycleStatus(
          teacherData,
          new Date(),
          { ignoreBreak: true }
        ).status
        : previousStatus;

      batch.update(teacherRef, {
        teacherStatus: resolvedStatus,
        breakUntil: fieldValue.delete(),
        updatedAt: fieldValue.serverTimestamp(),
      });
    }

    /*
     * Geçmiş raporlar için studentCount, dutyTeacherId,
     * dutyTeacherName ve students alt koleksiyonu korunur.
     */
    batch.update(sessionRef, {
      status: "completed",
      endedAt: fieldValue.serverTimestamp(),
      autoEnded: true,
      closedBy: "scheduledFunction",
      completedDutyTeacherId: dutyTeacherId || null,
      completedDutyTeacherName: claimedSessionData.dutyTeacherName || null,
      completedDutyTeacherPreviousStatus:
        claimedSessionData.dutyTeacherPreviousStatus || null,
      closingStartedAt: fieldValue.delete(),
      lastCloseError: fieldValue.delete(),
      updatedAt: fieldValue.serverTimestamp(),
    });

    await batch.commit();

    console.log(
      `Etüt oturumu otomatik kapatıldı: ${sessionRef.id}`
    );

    return true;
  } catch (error) {
    console.error(
      `Etüt oturumu kapatılamadı: ${sessionRef.id}`,
      error
    );

    await restoreSessionAfterFailure(sessionRef, error);

    throw error;
  }
}

async function closeActiveStudySessionsForInstitutionMode() {
  const activeSessionsSnapshot = await db
    .collection("studySessions")
    .where("status", "==", "active")
    .get();

  let checkedCount = 0;
  let closedCount = 0;
  let failedCount = 0;

  for (const sessionDoc of activeSessionsSnapshot.docs) {
    checkedCount += 1;

    try {
      const closed = await closeStudySession(sessionDoc);
      if (closed) {
        closedCount += 1;
      }
    } catch (error) {
      failedCount += 1;
    }
  }

  return {
    checkedCount,
    closedCount,
    failedCount,
  };
}

async function applyPlannedExamRuntime(now = new Date()) {
  const plannedExamRef = db.collection("settings").doc("plannedExam");
  const plannedExamDoc = await plannedExamRef.get();
  if (!plannedExamDoc.exists) return null;

  const plannedExamData = plannedExamDoc.data() || {};
  const allItems = plannedExamItems(plannedExamData);
  const items = allItems.filter((item) => item.end.getTime() > now.getTime());

  const runtimeRef = db.collection("settings").doc("runtimeState");
  const activeItem = allItems.find(
    (item) => item.status === PLANNED_EXAM_STATUS_ACTIVE
  );
  const dueItem = items.find(
    (item) =>
      item.status === PLANNED_EXAM_STATUS_SCHEDULED &&
      item.start.getTime() <= now.getTime() &&
      item.end.getTime() > now.getTime()
  );

  if (dueItem) {
    const nextItems = items.map((item) =>
      item.id === dueItem.id
        ? publicPlannedExamItem({
          ...item,
          status: PLANNED_EXAM_STATUS_ACTIVE,
        })
        : publicPlannedExamItem(item)
    );

    await runtimeRef.set({
      institutionMode: "exam",
      examType: dueItem.examType,
      examStartedAt: dueItem.scheduledStart,
      examEndsAt: dueItem.scheduledEnd,
      closedDate: null,
      isZumreOpen: false,
      isStudyOpen: false,
      isLunchBreak: false,
      currentPeriod: "exam",
      updatedAt: fieldValue.serverTimestamp(),
      plannedExamId: dueItem.id,
    }, { merge: true });

    await plannedExamRef.set({
      ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
      items: nextItems,
      activatedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });

    await deleteWaitingZumreQueuesWhenClosed({}, now, { forceClosed: true });
    await closeActiveStudySessionsForInstitutionMode();

    return {
      institutionMode: "exam",
      examType: dueItem.examType,
      examEndsAt: dueItem.scheduledEnd,
      applied: true,
    };
  }

  if (activeItem && activeItem.end.getTime() <= now.getTime()) {
    const nextItems = allItems
      .filter((item) => item.id !== activeItem.id)
      .map(publicPlannedExamItem);

    await plannedExamRef.set({
      ...plannedExamPrimaryFields(plannedExamItems({ items: nextItems })),
      items: nextItems,
      completedAt: fieldValue.serverTimestamp(),
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });

    await runtimeRef.set({
      institutionMode: "active",
      examType: null,
      examStartedAt: null,
      examEndsAt: null,
      plannedExamId: null,
      updatedAt: fieldValue.serverTimestamp(),
    }, { merge: true });

    return { completed: true };
  }

  if (items.length === 0) return null;

  return null;
}

// ============================================================
// SUNUCU TARAFI GENEL ZAMAN DURUMU
// ============================================================

exports.syncRuntimeSchedule = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: TIME_ZONE,
    region: REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async () => {
    const scheduleDoc = await db
      .collection("settings")
      .doc("zumreSchedule")
      .get();

    if (!scheduleDoc.exists) {
      console.log(
        "settings/zumreSchedule belgesi bulunamadı; runtimeState yazılmadı."
      );
      return;
    }

    const now = new Date();
    const plannedExamRuntime = await applyPlannedExamRuntime(now);
    if (plannedExamRuntime?.applied) {
      const expiredAppointmentsResult =
        await expireEndedScheduledAppointments(now);
      try {
        const noShowResult = await reconcileNoShowsAtDayEnd(now);
        if (!noShowResult.skipped) {
          console.log("Planlı zümre no-show doğrulaması tamamlandı.", noShowResult);
        }
      } catch (error) {
        console.error("Planlı zümre no-show doğrulaması tamamlanamadı.", error);
      }
      console.log("Planlı deneme mevcut deneme moduna alındı.", {
        ...plannedExamRuntime,
        expiredAppointmentsChecked: expiredAppointmentsResult.checkedCount,
        expiredAppointmentsExpired: expiredAppointmentsResult.expiredCount,
      });
      return;
    }

    const runtimeRef = db.collection("settings").doc("runtimeState");
    const runtimeDoc = await runtimeRef.get();
    const runtimeState = buildEffectiveRuntimeState(
      scheduleDoc.data() || {},
      runtimeDoc.data() || {},
      now
    );

    await runtimeRef.set(
      {
        ...runtimeState,
        updatedAt: fieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    const timeoutResult = await completeTimedOutZumreQueues(
      scheduleDoc.data() || {},
      now
    );
    const waitingCleanupResult = await deleteWaitingZumreQueuesWhenClosed(
      scheduleDoc.data() || {},
      now,
      {
        forceClosed: runtimeState.institutionMode !== "active",
      }
    );
    const expiredAppointmentsResult = await expireEndedScheduledAppointments(now);
    const teacherStatusResult = await syncTeacherStatuses(now);
    let noShowResult = { skipped: true };
    try {
      noShowResult = await reconcileNoShowsAtDayEnd(now);
    } catch (error) {
      console.error("Planlı zümre no-show doğrulaması tamamlanamadı.", error);
    }

    console.log("Runtime zaman durumu güncellendi.", {
      ...runtimeState,
      timedOutQueuesChecked: timeoutResult.checkedCount,
      timedOutQueuesCompleted: timeoutResult.completedCount,
      waitingQueuesChecked: waitingCleanupResult.checkedCount,
      waitingQueuesDeleted: waitingCleanupResult.deletedCount,
      waitingCleanupSkippedBecauseOpen:
        waitingCleanupResult.skippedBecauseOpen,
      expiredAppointmentsChecked: expiredAppointmentsResult.checkedCount,
      expiredAppointmentsExpired: expiredAppointmentsResult.expiredCount,
      teacherStatusesChecked: teacherStatusResult.checkedCount,
      teacherStatusesUpdated: teacherStatusResult.updatedCount,
      noShowReconciliation: noShowResult,
    });
  }
);

// ============================================================
// SUNUCU TARAFI ETÜT ZAMAN SENKRONİZASYONU
// ============================================================

exports.syncStudySessions = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: TIME_ZONE,
    region: REGION,
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async () => {
    const scheduleDoc = await db
      .collection("settings")
      .doc("zumreSchedule")
      .get();

    if (!scheduleDoc.exists) {
      console.log(
        "settings/zumreSchedule belgesi bulunamadı."
      );
      return;
    }

    const scheduleData = scheduleDoc.data() || {};
    const now = new Date();
    const runtimeDoc = await db
      .collection("settings")
      .doc("runtimeState")
      .get();
    const institutionState = resolveInstitutionMode(
      runtimeDoc.data() || {},
      now
    );

    if (institutionState.institutionMode === "exam") {
      const result = await closeActiveStudySessionsForInstitutionMode();
      console.log("Deneme modu aktif etüt kontrolü tamamlandı.", result);
      return;
    }

    const activeSessionsSnapshot = await db
      .collection("studySessions")
      .where("status", "==", "active")
      .get();

    if (activeSessionsSnapshot.empty) {
      console.log("Aktif etüt oturumu bulunamadı.");
      return;
    }

    let checkedCount = 0;
    let closedCount = 0;
    let failedCount = 0;

    for (const sessionDoc of activeSessionsSnapshot.docs) {
      checkedCount += 1;

      const sessionData = sessionDoc.data();

      if (!shouldCloseSession(sessionData, scheduleData, now)) {
        continue;
      }

      try {
        const closed = await closeStudySession(sessionDoc);

        if (closed) {
          closedCount += 1;
        }
      } catch (error) {
        failedCount += 1;
      }
    }

    console.log("Etüt zaman senkronizasyonu tamamlandı.", {
      checkedCount,
      closedCount,
      failedCount,
    });
  }
);

if (process.env.NODE_ENV === "test") {
  exports.__appointmentTest = {
    APPOINTMENT_OPTION_STEP_MINUTES,
    APPOINTMENT_PLANNED_CAPACITY_RATIO,
    APPOINTMENT_STUDENT_TRANSITION_BUFFER_MINUTES,
    appointmentMatchesBookingIdentity,
    appointmentMinutesInSlot,
    appointmentIdFor,
    appointmentLockId,
    appointmentOverlapsDocs,
    appointmentCanBecomeLive,
    appointmentShouldExpireScheduled,
    appointmentLinkedQueueId,
    appointmentIsFutureScheduled,
    appointmentTransferEligibility,
    buildSlotKey,
    buildAppointmentLinkedQueueData,
    canRequesterTransferAppointment,
    changedZumreDayKeys,
    transferEditUntilFor,
    dateKeyFromIstanbulDate,
    estimatedMinutesForQuestionCount,
    findContainingZumreSlot,
    generateAppointmentStartOptions,
    noShowVerificationUpdate,
    expiredAppointmentUpdate,
    expireEndedScheduledAppointments,
    noShowReconciliationCanWriteMarker,
    plannedExamItemsAfterCompletingActive,
    plannedExamConflictsWithAppointment,
    plannedExamDurationMinutes,
    plannedExamConflictDocs,
    plannedCapacityMinutesForSlot,
    reconcileNoShowAppointmentDocs,
    scheduleConflictDocsForChange,
    shouldRunNoShowReconciliation,
    verifiedNoShowHistoryEligible,
    verifiedNoShowPopupEligible,
  };
}
