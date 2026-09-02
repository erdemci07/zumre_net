from __future__ import annotations

import sys
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from models import (  # noqa: E402
    ClassReportData,
    DateRange,
    InstitutionSummaryData,
    QueueActivity,
    StudentReportRow,
    StudyAttendance,
    StudySession,
)
from reports import class_activity, class_tracking, institution_summary  # noqa: E402


ISTANBUL = ZoneInfo("Europe/Istanbul")
SUBJECTS = ["Matematik", "Fizik", "Kimya", "Biyoloji", "Türkçe", "Tarih"]


def _name(index: int) -> str:
    base = [
        "HASAN KAYA",
        "NAZLICAN YILMAZ",
        "ELİF DEMİR",
        "MERT CAN",
        "AYŞE DEMİR",
        "MEHMET YILMAZ",
        "HÜMEYRA EZEL",
        "FARUK AKSOY",
        "ZEYNEP SENA KARACA",
        "AHMET ALİ YÜKSEL",
    ]
    if index == 27:
        return "ZEYNEP SENA NUR BÜYÜKKARACAOĞLU"
    return f"{base[index % len(base)]} {index + 1}"


def build_sample_data():
    start = datetime(2026, 9, 1, tzinfo=ISTANBUL)
    date_range = DateRange(start, start + timedelta(days=7), "2026-09-01", "2026-09-07")
    students = [
        StudentReportRow(f"s{index:02d}", _name(index), "11-A", "", "")
        for index in range(30)
    ]
    student_map = {student.student_id: student for student in students}

    queues = []
    for index, student in enumerate(students):
        if index in {3, 11, 19, 26}:
            continue
        event_count = 1 + (index % 4)
        for offset in range(event_count):
            at = start + timedelta(
                days=(index + offset) % 6,
                hours=9 + ((index + offset) % 7),
                minutes=(index * 7 + offset * 11) % 50,
            )
            subject = SUBJECTS[(index + offset) % len(SUBJECTS)]
            queue = QueueActivity(student.student_id, student.student_name, subject, at)
            queues.append(queue)
            student.question_timeline.append(queue)
            student.questions_by_subject[subject] = (
                student.questions_by_subject.get(subject, 0) + 1
            )

    sessions = []
    attendances = []
    for day in range(5):
        session_start = start + timedelta(days=day, hours=16, minutes=30)
        session = StudySession(
            f"study-{day}",
            session_start,
            session_start.replace(hour=18, minute=0),
            0,
            None if day % 2 == 0 else "Berfin Hoca",
        )
        sessions.append(session)

        for index, student in enumerate(students):
            if (index + day) % 5 != 0:
                continue
            attendance = StudyAttendance(
                student.student_id,
                student.student_name,
                session.session_id,
                session.started_at,
                session.ended_at,
            )
            attendances.append(attendance)
            student_map[student.student_id].study_attendances.append(attendance)
        session.student_count = len(
            [item for item in attendances if item.session_id == session.session_id]
        )

    return (
        InstitutionSummaryData(date_range, queues, sessions, attendances),
        ClassReportData("11-A", date_range, students),
    )


def _page_count(path: Path) -> int | str:
    try:
        import fitz  # type: ignore

        with fitz.open(path) as doc:
            return doc.page_count
    except Exception:
        return "unknown"


def main():
    output = Path("tmp/report_samples")
    output.mkdir(parents=True, exist_ok=True)
    summary_data, class_data = build_sample_data()
    files = {
        "institution_summary_colored_sample.pdf": institution_summary.render(summary_data),
        "class_tracking_table_sample.pdf": class_tracking.render(class_data),
        "class_activity_table_sample.pdf": class_activity.render(class_data),
    }
    for name, content in files.items():
        target = output / name
        target.write_bytes(content)
        print(f"{target.resolve()} pages={_page_count(target)}")


if __name__ == "__main__":
    main()
