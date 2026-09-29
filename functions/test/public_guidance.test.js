const test = require("node:test");
const assert = require("node:assert/strict");
const { createSmsService, hashOtp, maskPhone } = require("../services/sms_service");
const { normalizeAvailability, normalizePhone, publicUpcomingAppointments, slotOptions } = require("../services/public_guidance");

test("guardian phone normalization matches canonical Turkish GSM values", () => {
  assert.equal(normalizePhone("+90 (555) 123 45 67"), "5551234567");
  assert.equal(normalizePhone("05551234567"), "5551234567");
  assert.equal(normalizePhone("5551234567"), "5551234567");
  assert.equal(normalizePhone("555123456"), "");
  assert.equal(maskPhone("5551234567"), "*** *** **67");
});

test("availability excludes closed dates, busy slots and time outside counselor periods", () => {
  const availability = normalizeAvailability({ weekly: { monday: [{ start: "13:30", end: "14:30" }] }, closedDates: ["2026-09-28"], slotMinutes: 20 });
  assert.deepEqual(slotOptions(availability, "2026-09-28", new Date("2026-09-20T09:00:00Z")), []);
  assert.deepEqual(slotOptions(availability, "2026-10-05", new Date("2026-09-20T09:00:00Z"), [{ appointmentDate: "2026-10-05", time: "13:50", status: "approved" }]), ["13:30", "14:10"]);
});

test("OTP is hashed and disabled Netgsm never delivers", async () => {
  assert.notEqual(hashOtp("123456", "salt"), "123456");
  const service = createSmsService({ SMS_PROVIDER: "netgsm", NETGSM_ENABLED: "false", NODE_ENV: "production" });
  assert.deepEqual(await service.sendOtp({}), { delivered: false, provider: "netgsm", disabled: true });
  const mock = createSmsService({ SMS_PROVIDER: "mock", NODE_ENV: "test" });
  assert.equal((await mock.sendOtp({})).mock, true);
  const productionMock = createSmsService({ SMS_PROVIDER: "mock", NODE_ENV: "production" });
  assert.equal((await productionMock.sendOtp({})).disabled, true);
});

test("public upcoming appointment summary excludes terminal and past records", () => {
  const result = publicUpcomingAppointments([
    { appointmentDate: "2026-10-02", time: "14:20", counselorName: "Ayse", status: "approved", internalNote: "never returned" },
    { appointmentDate: "2026-10-03", time: "13:30", counselorName: "Deniz", status: "pending" },
    { appointmentDate: "2026-10-01", time: "13:30", status: "cancelled" },
    { appointmentDate: "2026-10-01", time: "13:30", status: "completed" },
    { appointmentDate: "2026-09-28", time: "13:30", status: "approved" },
  ], new Date("2026-10-01T08:00:00Z"));
  assert.deepEqual(result, [
    { date: "2026-10-02", time: "14:20", counselorName: "Ayse", status: "approved" },
    { date: "2026-10-03", time: "13:30", counselorName: "Deniz", status: "pending" },
  ]);
});
