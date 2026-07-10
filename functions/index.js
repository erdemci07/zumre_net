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

// ============================================================
// KULLANICI ŞİFRESİ GÜNCELLEME
// ============================================================

exports.updateUserPassword = onCall(
  {
    region: REGION,
  },
  async (request) => {
    try {
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
        error?.message || "Şifre güncellenemedi."
      );
    }
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
     * Seçilmiş branş öğretmenini etüt öncesindeki durumuna döndür.
     */
    const dutyTeacherId = claimedSessionData.dutyTeacherId;

    if (dutyTeacherId) {
      const teacherRef = db
        .collection("users")
        .doc(dutyTeacherId);

      const previousStatus =
        claimedSessionData.dutyTeacherPreviousStatus ||
        "available";

      batch.update(teacherRef, {
        teacherStatus: previousStatus,
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

    const activeSessionsSnapshot = await db
      .collection("studySessions")
      .where("status", "==", "active")
      .get();

    if (activeSessionsSnapshot.empty) {
      console.log("Aktif etüt oturumu bulunamadı.");
      return;
    }

    const now = new Date();

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