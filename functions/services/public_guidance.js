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
function istanbulDateKey(now = new Date()) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Istanbul" }).format(now);
}
function publicUpcomingAppointments(appointments = [], now = new Date()) {
  const today = istanbulDateKey(now);
  return appointments
    .filter((item) => ACTIVE_STATUSES.has(item.status || "pending"))
    .filter((item) => validDateKey(clean(item.appointmentDate)) && clean(item.appointmentDate) >= today)
    .map((item) => ({
      date: clean(item.appointmentDate),
      time: clean(item.time),
      counselorName: clean(item.counselorName),
      status: clean(item.status || "pending"),
    }))
    .sort((left, right) => `${left.date} ${left.time}`.localeCompare(`${right.date} ${right.time}`));
}
function opaqueToken() { return crypto.randomBytes(32).toString("base64url"); }
function otpCode() { return String(crypto.randomInt(0, 1000000)).padStart(6, "0"); }
function genericVerificationError(HttpsError) { return new HttpsError("failed-precondition", "Bilgiler doğrulanamadı. Lütfen bilgilerinizi kontrol edin."); }

module.exports = {
  ACTIVE_STATUSES, OTP_COOLDOWN_MS, OTP_DAILY_LIMIT, OTP_MAX_ATTEMPTS, OTP_TTL_MS, PUBLIC_SESSION_TTL_MS,
  clean, dateWeekday, genericVerificationError, hashOtp, istanbulDateKey, maskPhone, normalizeAvailability, normalizePhone,
  normalizeUsername, opaqueToken, otpCode, publicUpcomingAppointments, slotOptions, timeToMinutes, validDateKey,
};
