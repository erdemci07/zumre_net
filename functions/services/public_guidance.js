const crypto = require("crypto");
const { hashOtp, maskPhone } = require("./sms_service");

const WEEKDAYS = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
const ACTIVE_STATUSES = new Set(["pending", "approved", "in_progress"]);
const OTP_TTL_MS = 3 * 60 * 1000;
const OTP_COOLDOWN_MS = 60 * 1000;
const OTP_MAX_ATTEMPTS = 5;
const OTP_DAILY_LIMIT = 5;
const PUBLIC_SESSION_TTL_MS = 15 * 60 * 1000;

function clean(value) { return String(value || "").replace(/\s+/g, " ").trim(); }
function normalizeUsername(value) { return clean(value).replace(/\s+/g, "").toLowerCase(); }
function normalizePhone(value) {
  let digits = String(value || "").replace(/\D/g, "");
  if (digits.startsWith("0090")) digits = digits.slice(4);
  else if (digits.startsWith("90") && digits.length === 12) digits = digits.slice(2);
  else if (digits.startsWith("0") && digits.length === 11) digits = digits.slice(1);
  return /^5\d{9}$/.test(digits) ? digits : "";
}
function timeToMinutes(value) {
  const match = /^(\d{1,2}):(\d{2})$/.exec(clean(value));
  if (!match) return -1;
  const hour = Number(match[1]); const minute = Number(match[2]);
  return hour < 24 && minute < 60 ? hour * 60 + minute : -1;
}
function dateWeekday(dateKey) { return WEEKDAYS[new Date(`${dateKey}T12:00:00Z`).getUTCDay()]; }
function validDateKey(dateKey) { return /^\d{4}-\d{2}-\d{2}$/.test(dateKey) && !Number.isNaN(Date.parse(`${dateKey}T12:00:00Z`)); }
function availabilityValidationError(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return "Veli görüşme saatleri geçersiz.";
  }
  if (raw.weekly !== undefined &&
      (!raw.weekly || typeof raw.weekly !== "object" || Array.isArray(raw.weekly))) {
    return "Haftalık veli görüşme programı geçersiz.";
  }
  const labels = {
    sunday: "Pazar", monday: "Pazartesi", tuesday: "Salı",
    wednesday: "Çarşamba", thursday: "Perşembe", friday: "Cuma",
    saturday: "Cumartesi",
  };
  for (const day of WEEKDAYS) {
    const rawSlots = raw.weekly?.[day];
    if (rawSlots !== undefined && !Array.isArray(rawSlots)) {
      return `${labels[day]} görüşme saatleri geçersiz.`;
    }
    const slots = rawSlots || [];
    if (slots.length > 12) return `${labels[day]} için çok fazla saat aralığı var.`;
    for (const slot of slots) {
      const start = clean(slot?.start);
      const end = clean(slot?.end);
      if (!/^\d{2}:\d{2}$/.test(start) ||
          !/^\d{2}:\d{2}$/.test(end) ||
          timeToMinutes(start) < 0 ||
          timeToMinutes(end) <= timeToMinutes(start)) {
        return `${labels[day]} için başlangıç ve bitiş saatlerini kontrol edin.`;
      }
    }
  }
  if (raw.slotMinutes !== undefined &&
      ![15, 20, 30].includes(Number(raw.slotMinutes))) {
    return "Veli görüşme süresi geçersiz.";
  }
  if (raw.closedDates !== undefined &&
      (!Array.isArray(raw.closedDates) || raw.closedDates.some((value) => !validDateKey(value)))) {
    return "Kapalı tarih bilgisi geçersiz.";
  }
  return null;
}
function normalizeAvailability(raw = {}) {
  const weekly = {};
  for (const day of WEEKDAYS) {
    const slots = Array.isArray(raw.weekly?.[day]) ? raw.weekly[day] : [];
    weekly[day] = slots.map((slot) => ({ start: clean(slot?.start), end: clean(slot?.end) }))
      .filter((slot) => timeToMinutes(slot.start) >= 0 && timeToMinutes(slot.end) > timeToMinutes(slot.start));
  }
  return { weekly, closedDates: [...new Set((Array.isArray(raw.closedDates) ? raw.closedDates : []).filter(validDateKey))], slotMinutes: [15, 20, 30].includes(Number(raw.slotMinutes)) ? Number(raw.slotMinutes) : 20 };
}
function slotOptions(availability, dateKey, now = new Date(), appointments = []) {
  if (!validDateKey(dateKey) || availability.closedDates.includes(dateKey)) return [];
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(now);
  const nowParts = new Intl.DateTimeFormat("en-GB", { timeZone: "Europe/Istanbul", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).formatToParts(now);
  const nowMinutes = Number(nowParts.find((part) => part.type === "hour")?.value || 0) * 60 + Number(nowParts.find((part) => part.type === "minute")?.value || 0);
  const busy = new Set(appointments.filter((item) => ACTIVE_STATUSES.has(item.status || "pending") && item.appointmentDate === dateKey).map((item) => clean(item.time)));
  const options = [];
  for (const period of availability.weekly[dateWeekday(dateKey)] || []) {
    for (let minute = timeToMinutes(period.start); minute + availability.slotMinutes <= timeToMinutes(period.end); minute += availability.slotMinutes) {
      const time = `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`;
      if ((dateKey !== today || minute > nowMinutes) && !busy.has(time)) options.push(time);
    }
  }
  return options;
}
function availableDateOptions(availability, now = new Date(), appointments = [], count = 7) {
  const normalized = normalizeAvailability(availability);
  const firstDate = new Date(`${istanbulDateKey(now)}T12:00:00.000Z`);
  const results = [];
  for (let offset = 0; offset < 366 && results.length < count; offset += 1) {
    const date = new Date(firstDate);
    date.setUTCDate(firstDate.getUTCDate() + offset);
    const dateKey = date.toISOString().slice(0, 10);
    const slots = slotOptions(normalized, dateKey, now, appointments);
    if (slots.length > 0) results.push({ date: dateKey, slots });
  }
  return results;
}
function istanbulDateKey(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(now);
}
function publicUpcomingAppointments(appointments = [], now = new Date()) {
  const today = istanbulDateKey(now);
  return appointments
    .filter((item) => ACTIVE_STATUSES.has(item.status || "pending"))
    .filter((item) => validDateKey(clean(item.appointmentDate)) && clean(item.appointmentDate) >= today)
    .map((item) => ({
      id: clean(item.id),
      date: clean(item.appointmentDate),
      time: clean(item.time),
      counselorName: clean(item.counselorName),
      status: clean(item.status || "pending"),
      participantType: clean(item.participantType || "guardian"),
    }))
    .sort((left, right) => `${left.date} ${left.time}`.localeCompare(`${right.date} ${right.time}`));
}
function opaqueToken() { return crypto.randomBytes(32).toString("base64url"); }
function otpCode() { return String(crypto.randomInt(0, 1000000)).padStart(6, "0"); }
function otpAttemptDecision(challenge = {}, code = "") {
  const attempts = Math.max(0, Number(challenge.attempts || 0));
  if (attempts >= OTP_MAX_ATTEMPTS) {
    return { status: "blocked", attempts };
  }

  const submittedHash = hashOtp(String(code), challenge.salt);
  const expectedHash = String(challenge.codeHash || "");
  const matches = submittedHash.length === expectedHash.length &&
    crypto.timingSafeEqual(Buffer.from(submittedHash), Buffer.from(expectedHash));

  return matches
    ? { status: "verified", attempts }
    : { status: "invalid", attempts: attempts + 1 };
}
function genericVerificationError(HttpsError) { return new HttpsError("failed-precondition", "Bilgiler doğrulanamadı. Lütfen bilgilerinizi kontrol edin."); }

module.exports = {
  ACTIVE_STATUSES, OTP_COOLDOWN_MS, OTP_DAILY_LIMIT, OTP_MAX_ATTEMPTS, OTP_TTL_MS, PUBLIC_SESSION_TTL_MS,
  availabilityValidationError, availableDateOptions, clean, dateWeekday, genericVerificationError, hashOtp, istanbulDateKey, maskPhone, normalizeAvailability, normalizePhone,
  normalizeUsername, opaqueToken, otpAttemptDecision, otpCode, publicUpcomingAppointments, slotOptions, timeToMinutes, validDateKey,
};
