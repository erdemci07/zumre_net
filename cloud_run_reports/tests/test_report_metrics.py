from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from models import (
    ClassReportData,
    DateRange,
    InstitutionSummaryData,
    QueueActivity,
    StudentReportRow,
    StudyAttendance,
    StudySession,
)
from report_metrics import class_totals, institution_metrics


ISTANBUL = ZoneInfo("Europe/Istanbul")


def _range():
    start = datetime(2026, 9, 1, tzinfo=ISTANBUL)
    return DateRange(start, start + timedelta(days=1), "2026-09-01", "2026-09-01")


def test_completed_queue_document_counts_as_one_question():
    data = InstitutionSummaryData(
        date_range=_range(),
        completed_questions=[
            QueueActivity("s1", "Ayşe Yılmaz", "Matematik", datetime(2026, 9, 1, 10, tzinfo=ISTANBUL)),
            QueueActivity("s1", "Ayşe Yılmaz", "Matematik", datetime(2026, 9, 1, 11, tzinfo=ISTANBUL)),
            QueueActivity("s2", "Mehmet Kaya", "Fizik", datetime(2026, 9, 1, 12, tzinfo=ISTANBUL)),
        ],
        study_sessions=[],
        study_attendances=[],
    )

    metrics = institution_metrics(data)

    assert metrics["completed_question_count"] == 3
    assert metrics["zumre_student_count"] == 2
    assert metrics["subject_counts"] == {"Matematik": 2, "Fizik": 1}


def test_study_students_are_distinct_in_institution_summary():
    started_at = datetime(2026, 9, 1, 16, 30, tzinfo=ISTANBUL)
    data = InstitutionSummaryData(
        date_range=_range(),
        completed_questions=[],
        study_sessions=[
            StudySession("session-1", started_at, started_at.replace(hour=18), 2, None),
        ],
        study_attendances=[
            StudyAttendance("s1", "Ayşe Yılmaz", "session-1", started_at, started_at.replace(hour=18)),
            StudyAttendance("s1", "Ayşe Yılmaz", "session-1", started_at, started_at.replace(hour=18)),
            StudyAttendance("s2", "Mehmet Kaya", "session-1", started_at, started_at.replace(hour=18)),
        ],
    )

    metrics = institution_metrics(data)

    assert metrics["study_student_count"] == 2
    assert metrics["completed_study_session_count"] == 1


def test_class_report_keeps_zero_activity_students():
    active = StudentReportRow("s1", "Aktif Öğrenci", "11-A", "", "")
    passive = StudentReportRow("s2", "Sessiz Öğrenci", "11-A", "", "")
    active.question_timeline.append(
        QueueActivity("s1", "Aktif Öğrenci", "Kimya", datetime(2026, 9, 1, 13, tzinfo=ISTANBUL))
    )
    data = ClassReportData("11-A", _range(), [active, passive])

    totals = class_totals(data)

    assert totals == {
        "student_count": 2,
        "question_count": 1,
        "study_attendance_count": 0,
    }
