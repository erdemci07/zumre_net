const WEEKLY_GUIDANCE_TASK_TITLES = Object.freeze([
  "Haftalık Ödev Kontrolü",
  "Akademik Takip",
  "Hedef Kontrolü",
  "Ders Programı Kontrolü",
]);

const WEEKLY_GUIDANCE_TASK_SCHEDULES = Object.freeze([
  "Her Pazartesi",
  "Her Salı",
  "Her Çarşamba",
  "Her Perşembe",
  "Her Cuma",
  "Her Cumartesi",
  "Her Pazar",
]);

function clean(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

function parseWeeklyGuidanceTaskInput(raw = {}) {
  const input = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
  const studentId = clean(input.studentId);
  const title = clean(input.title);
  const schedule = clean(input.schedule);

  if (!studentId || studentId.length > 128 || studentId.includes("/")) {
    return { error: "Öğrenci seçimi geçersiz." };
  }
  if (!WEEKLY_GUIDANCE_TASK_TITLES.includes(title)) {
    return { error: "Haftalık takip görevi geçersiz." };
  }
  if (!WEEKLY_GUIDANCE_TASK_SCHEDULES.includes(schedule)) {
    return { error: "Haftalık takip günü geçersiz." };
  }

  return { studentId, title, schedule };
}

module.exports = {
  WEEKLY_GUIDANCE_TASK_SCHEDULES,
  WEEKLY_GUIDANCE_TASK_TITLES,
  parseWeeklyGuidanceTaskInput,
};
