const test = require("node:test");
const assert = require("node:assert/strict");
const { createSmsService, hashOtp, maskPhone } = require("../services/sms_service");
const { OTP_MAX_ATTEMPTS, availabilityValidationError, normalizeAvailability, normalizePhone, otpAttemptDecision, publicUpcomingAppointments, slotOptions } = require("../services/public_guidance");

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

test("availability input rejects incomplete and invalid time ranges", () => {
  const valid = {
    weekly: { monday: [{ start: "08:30", end: "17:30" }] },
    closedDates: [],
    slotMinutes: 20,
  };
  assert.equal(availabilityValidationError(valid), null);

  for (const [start, end] of [
    ["8:30", "17:30"],
    ["08:3", "17:30"],
    ["24:00", "17:30"],
    ["08:60", "17:30"],
    ["17:30", "17:30"],
    ["18:00", "17:30"],
  ]) {
    assert.notEqual(
      availabilityValidationError({
        weekly: { monday: [{ start, end }] },
        closedDates: [],
        slotMinutes: 20,
      }),
      null
    );
  }
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

test("wrong OTP attempts advance to the configured limit without weakening valid-code checks", () => {
  const challenge = {
    attempts: 0,
    salt: "salt",
    codeHash: hashOtp("123456", "salt"),
  };
  assert.deepEqual(otpAttemptDecision(challenge, "000000"), {
    status: "invalid",
    attempts: 1,
  });
  assert.deepEqual(
    otpAttemptDecision({ ...challenge, attempts: OTP_MAX_ATTEMPTS - 1 }, "000000"),
    { status: "invalid", attempts: OTP_MAX_ATTEMPTS }
  );
  assert.deepEqual(
    otpAttemptDecision({ ...challenge, attempts: OTP_MAX_ATTEMPTS }, "123456"),
    { status: "blocked", attempts: OTP_MAX_ATTEMPTS }
  );
  assert.deepEqual(otpAttemptDecision(challenge, "123456"), {
    status: "verified",
    attempts: 0,
  });
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
