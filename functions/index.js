const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const fieldValue = admin.firestore.FieldValue;

const REGION = "us-central1";
const TIME_ZONE = "Europe/Istanbul";

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
        "internal",
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
        "internal",
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

    const userRef = db.collection("users").doc(uid);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Kullanıcı kaydı bulunamadı."
      );
    }

    const userData = userDoc.data() || {};

    if (userData.role === "admin") {
      const adminsSnapshot = await db
        .collection("users")
        .where("role", "==", "admin")
        .limit(2)
        .get();

      if (adminsSnapshot.size <= 1) {
        throw new HttpsError(
          "failed-precondition",
          "Sistemdeki son yönetici hesabı silinemez."
        );
      }
    }

    await assertNoActiveUserOperation(uid, userData);

    try {
      try {
        await admin.auth().deleteUser(uid);
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
        "internal",
        mapAuthError(error, "Kullanıcı silinemedi.")
      );
    }
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
        "internal",
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
