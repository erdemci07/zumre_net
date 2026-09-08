const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

const REGION = "us-central1";
const TIME_ZONE = "Europe/Istanbul";
const BULK_DELETE_LIMIT = 500;
const BULK_DELETE_CHUNK_SIZE = 25;
const AUTH_DELETE_RETRY_DELAYS_MS = [750, 1500, 3000];

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

function getStudySlots(scheduleData, weekday) {
  const rawSlots = isWeekend(weekday)
    ? scheduleData.weekendStudySlots
    : scheduleData.weekdayStudySlots;

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

function getZumreSlots(scheduleData, weekday) {
  const rawSlots = isWeekend(weekday)
    ? scheduleData.weekendSlots
    : scheduleData.weekdaySlots;

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
  const zumreSlots = getZumreSlots(scheduleData, nowParts.weekday);
  const studySlots = getStudySlots(scheduleData, nowParts.weekday);
  const lunchBreak = scheduleData.lunchBreak || {};
  const lunchSlots = [
    {
      start: String(lunchBreak.start ?? "12:20"),
      end: String(lunchBreak.end ?? "13:00"),
      startMinutes: timeToMinutes(String(lunchBreak.start ?? "12:20")),
      endMinutes: timeToMinutes(String(lunchBreak.end ?? "13:00")),
    },
  ].filter(
    (slot) =>
      slot.startMinutes >= 0 &&
      slot.endMinutes >= 0 &&
      slot.endMinutes > slot.startMinutes
  );

  const isLunchBreak = isNowInSlots(currentMinutes, lunchSlots);
  const isZumreOpen = isNowInSlots(currentMinutes, zumreSlots);
  const isStudyOpen = isNowInSlots(currentMinutes, studySlots);

  return {
    isZumreOpen,
    isLunchBreak,
    isStudyOpen,
    currentPeriod: isLunchBreak
      ? "lunch"
      : isStudyOpen
        ? "study"
        : isZumreOpen
          ? "zumre"
          : "closed",
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
          updatedAt: fieldValue.serverTimestamp(),
          updatedBy: adminUid,
        },
        { merge: true }
      );

      return { ok: true, mode: "active" };
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

      transaction.update(queueRef, {
        status: "completed",
        completedAt: fieldValue.serverTimestamp(),
        updatedAt: fieldValue.serverTimestamp(),
      });

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
    const teacherStatusResult = await syncTeacherStatuses(now);

    console.log("Runtime zaman durumu güncellendi.", {
      ...runtimeState,
      timedOutQueuesChecked: timeoutResult.checkedCount,
      timedOutQueuesCompleted: timeoutResult.completedCount,
      waitingQueuesChecked: waitingCleanupResult.checkedCount,
      waitingQueuesDeleted: waitingCleanupResult.deletedCount,
      waitingCleanupSkippedBecauseOpen:
        waitingCleanupResult.skippedBecauseOpen,
      teacherStatusesChecked: teacherStatusResult.checkedCount,
      teacherStatusesUpdated: teacherStatusResult.updatedCount,
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
