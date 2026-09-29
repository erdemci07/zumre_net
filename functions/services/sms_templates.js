function otpMessage(code) {
  return `Bilim Kalesi doğrulama kodunuz: ${code}. Kod 3 dakika geçerlidir.`;
}

function confirmationMessage({ date, time }) {
  return `Bilim Kalesi: Rehberlik görüşmeniz ${date} ${time} için oluşturulmuştur.`;
}

function reminderMessage({ date, time }) {
  return `Bilim Kalesi: Rehberlik görüşmeniz ${date} ${time}'de gerçekleştirilecektir.`;
}

module.exports = { confirmationMessage, otpMessage, reminderMessage };
