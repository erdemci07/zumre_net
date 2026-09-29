const crypto = require("crypto");

function smsConfig(env = process.env) {
  return {
    provider: String(env.SMS_PROVIDER || "netgsm").toLowerCase(),
    netgsmEnabled: String(env.NETGSM_ENABLED || "false") === "true",
    isDevelopment: env.FUNCTIONS_EMULATOR === "true" || env.NODE_ENV === "test" || env.NODE_ENV === "development",
  };
}

function maskPhone(phone) {
  const digits = String(phone || "").replace(/\D/g, "");
  return digits.length === 10 ? `*** *** **${digits.slice(-2)}` : "*** *** **";
}

function hashOtp(code, salt) {
  return crypto.createHash("sha256").update(`${salt}:${code}`).digest("hex");
}

function createSmsService(env = process.env) {
  const config = smsConfig(env);
  const disabled = async () => ({ delivered: false, provider: config.provider, disabled: true });
  const mock = async () => ({ delivered: false, provider: "mock", mock: true });

  const netgsm = async ({ to, message }) => {
    if (!config.netgsmEnabled) return disabled();
    const user = String(env.NETGSM_USER || "");
    const password = String(env.NETGSM_PASSWORD || env.NETGSM_API_SECRET || "");
    const header = String(env.NETGSM_HEADER || "");
    if (!user || !password || !header) {
      throw new Error("Netgsm yapılandırması eksik.");
    }
    const response = await fetch("https://api.netgsm.com.tr/sms/send/get", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ usercode: user, password, msgheader: header, gsmno: `90${to}`, message }),
    });
    if (!response.ok) throw new Error("Netgsm gönderimi başarısız.");
    return { delivered: true, provider: "netgsm" };
  };

  // Netgsm credentials are intentionally read only at provider activation time.
  // No credential, OTP value, or recipient is written to logs by this layer.
  const send = config.provider === "mock" && config.isDevelopment
    ? mock
    : config.provider === "netgsm" ? netgsm : disabled;
  return {
    config,
    sendOtp: send,
    sendAppointmentConfirmation: send,
    sendAppointmentReminder: send,
  };
}

module.exports = { createSmsService, hashOtp, maskPhone, smsConfig };
