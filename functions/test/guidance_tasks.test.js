const test = require("node:test");
const assert = require("node:assert/strict");
const {
  WEEKLY_GUIDANCE_TASK_SCHEDULES,
  WEEKLY_GUIDANCE_TASK_TITLES,
  parseWeeklyGuidanceTaskInput,
} = require("../services/guidance_tasks");

test("weekly guidance task input accepts every supported title and day", () => {
  for (const title of WEEKLY_GUIDANCE_TASK_TITLES) {
    for (const schedule of WEEKLY_GUIDANCE_TASK_SCHEDULES) {
      assert.deepEqual(
        parseWeeklyGuidanceTaskInput({
          studentId: "student-1",
          title,
          schedule,
        }),
        { studentId: "student-1", title, schedule }
      );
    }
  }
});

test("weekly guidance task input rejects unsupported titles and days", () => {
  assert.deepEqual(
    parseWeeklyGuidanceTaskInput({
      studentId: "student-1",
      title: "Serbest görev",
      schedule: "Her Pazartesi",
    }),
    { error: "Haftalık takip görevi geçersiz." }
  );
  assert.deepEqual(
    parseWeeklyGuidanceTaskInput({
      studentId: "student-1",
      title: "Akademik Takip",
      schedule: "Her gün",
    }),
    { error: "Haftalık takip günü geçersiz." }
  );
});

test("weekly guidance task input rejects unsafe student document ids", () => {
  for (const studentId of ["", "students/student-1", "x".repeat(129)]) {
    assert.deepEqual(
      parseWeeklyGuidanceTaskInput({
        studentId,
        title: "Akademik Takip",
        schedule: "Her Salı",
      }),
      { error: "Öğrenci seçimi geçersiz." }
    );
  }
});
