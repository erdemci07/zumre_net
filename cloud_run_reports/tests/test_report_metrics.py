from __future__ import annotations

from datetime import datetime, timedelta
from unittest.mock import Mock
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
from report_metrics import class_activity_summary, class_totals, institution_metrics
import firestore_queries
from firestore_queries import build_guidance_activity_summary, fetch_class_students


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


def test_class_students_can_be_limited_to_guidance_assignments():
    from unittest.mock import Mock

    documents = [
        Mock(
            id="assigned",
            to_dict=Mock(
                return_value={
                    "fullName": "Atanmış Öğrenci",
                    "className": "11-A",
                    "guidanceCounselorId": "counselor-1",
                }
            ),
        ),
        Mock(
            id="unassigned",
            to_dict=Mock(
                return_value={
                    "fullName": "Diğer Öğrenci",
                    "className": "11-A",
                    "guidanceCounselorId": "counselor-2",
                }
            ),
        ),
    ]
    query = Mock()
    query.where.return_value = query
    query.stream.return_value = documents
    collection = Mock()
    collection.where.return_value = query
    database = Mock()
    database.collection.return_value = collection

    students = fetch_class_students(
        database,
        "11-A",
        counselor_id="counselor-1",
    )

    assert [student.student_id for student in students] == ["assigned"]


def test_guidance_activity_summary_counts_student_and_guardian_meetings_and_keeps_zeroes(
    monkeypatch,
):
    def document(document_id, data):
        item = Mock()
        item.id = document_id
        item.to_dict.return_value = data
        return item

    users_query = Mock()
    users_query.where.return_value = users_query
    users_query.stream.return_value = [
        document("counselor-1", {"fullName": "Ayşe Yılmaz", "role": "guidance"}),
        document("counselor-2", {"name": "Mehmet Kaya", "role": "guidance"}),
    ]
    appointments_query = Mock()
    appointments_query.where.return_value = appointments_query
    appointments_query.stream.return_value = [
        document(
            "student-meeting",
            {
                "counselorId": "counselor-1",
                "participantType": "student",
                "status": "completed",
            },
        ),
        document(
            "guardian-meeting",
            {
                "counselorId": "counselor-1",
                "source": "parent_public_booking",
                "status": "completed",
            },
        ),
    ]
    database = Mock()
    database.collection.side_effect = lambda name: {
        "users": Mock(where=Mock(return_value=users_query)),
        "guidanceAppointments": Mock(where=Mock(return_value=appointments_query)),
    }[name]
    monkeypatch.setattr(firestore_queries.firestore, "client", lambda: database)

    result = build_guidance_activity_summary("2026-09-01", "2026-09-30")

    assert result["counselors"] == [
        {
            "id": "counselor-1",
            "name": "Ayşe Yılmaz",
            "student_meeting_count": 1,
            "guardian_meeting_count": 1,
            "total_meeting_count": 2,
        },
        {
            "id": "counselor-2",
            "name": "Mehmet Kaya",
            "student_meeting_count": 0,
            "guardian_meeting_count": 0,
            "total_meeting_count": 0,
        },
    ]
    assert appointments_query.where.call_count == 3


def test_class_activity_summary_keeps_recorded_teacher_and_omits_legacy_teacher():
    student = StudentReportRow("s1", "Ayşe Yılmaz", "11-A", "", "")
    student.question_timeline.extend([
        QueueActivity("s1", "Ayşe Yılmaz", "Matematik", datetime(2026, 9, 1, 13, tzinfo=ISTANBUL), teacher_name="Ahmet Yılmaz"),
        QueueActivity("s1", "Ayşe Yılmaz", "Matematik", datetime(2026, 9, 1, 14, tzinfo=ISTANBUL)),
    ])

    summary = class_activity_summary(ClassReportData("11-A", _range(), [student]))

    assert summary == [{"subject": "Matematik", "question_count": 2, "teacher_names": ["Ahmet Yılmaz"]}]
