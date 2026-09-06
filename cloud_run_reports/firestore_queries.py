from __future__ import annotations

import logging
from datetime import datetime, timedelta
from typing import Iterable
from zoneinfo import ZoneInfo

from firebase_admin import firestore
from google.cloud.firestore_v1 import FieldFilter

from models import (
    ClassReportData,
    DateRange,
    InstitutionSummaryData,
    QueueActivity,
    StudentReportRow,
    StudyAttendance,
    StudySession,
)


ISTANBUL = ZoneInfo("Europe/Istanbul")
LOGGER = logging.getLogger(__name__)


def parse_date_range(start_date: str, end_date: str) -> DateRange:
    try:
        start_day = datetime.strptime(start_date, "%Y-%m-%d").date()
        end_day = datetime.strptime(end_date, "%Y-%m-%d").date()
    except ValueError:
        raise ValueError("Tarih formatı YYYY-MM-DD olmalıdır.")

    if end_day < start_day:
        raise ValueError("Bitiş tarihi başlangıç tarihinden önce olamaz.")

    if (end_day - start_day).days > 92:
      raise ValueError("Rapor tarih aralığı en fazla 93 gün olabilir.")

    start = datetime.combine(start_day, datetime.min.time(), tzinfo=ISTANBUL)
    end = datetime.combine(end_day, datetime.min.time(), tzinfo=ISTANBUL)

    return DateRange(
        start=start,
        end=end + timedelta(days=1),
        start_label=start_date,
        end_label=end_date,
    )


def _to_datetime(value):
    if value is None:
        return None

    if hasattr(value, "to_datetime"):
        return value.to_datetime().astimezone(ISTANBUL)

    if isinstance(value, datetime):
        if value.tzinfo is None:
            return value.replace(tzinfo=ZoneInfo("UTC")).astimezone(ISTANBUL)
        return value.astimezone(ISTANBUL)

    return None


def _scheduled_datetime(slot_date, slot_time):
    date_text = _clean(slot_date)
    time_text = _clean(slot_time)

    if not date_text or not time_text:
        return None

    try:
        day = datetime.strptime(date_text, "%Y-%m-%d").date()
        hour, minute = [int(part) for part in time_text.split(":", 1)]
    except (TypeError, ValueError):
        return None

    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        return None

    return datetime(day.year, day.month, day.day, hour, minute, tzinfo=ISTANBUL)


def _clean(value, fallback=""):
    text = str(value or "").strip()
    return text or fallback


def _safe_int(value, fallback=0):
    if isinstance(value, bool):
        return fallback
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return fallback
    return fallback


def _teacher_name_from_data(data: dict) -> str:
    return _clean(data.get("fullName") or data.get("name") or data.get("email"))


def _log_skip(collection: str, doc_id: str, reason: str):
    LOGGER.warning(
        "Skipping report document: collection=%s docId=%s reason=%s",
        collection,
        doc_id,
        reason,
    )


def normalize_queue_doc(doc) -> QueueActivity | None:
    try:
        data = doc.to_dict() or {}
    except Exception as exc:
        LOGGER.exception(
            "Failed to read report document: collection=queues docId=%s type=%s",
            getattr(doc, "id", "unknown"),
            type(exc).__name__,
        )
        return None

    completed_at = _to_datetime(data.get("completedAt") or data.get("updatedAt"))
    if completed_at is None:
        _log_skip("queues", doc.id, "missing_completedAt")
        return None

    return QueueActivity(
        student_id=_clean(data.get("studentId"), doc.id),
        student_name=_clean(
            data.get("studentName") or data.get("studentFullName"),
            "Öğrenci",
        ),
        subject=_clean(data.get("subject"), "Bilinmeyen"),
        completed_at=completed_at,
    )


def fetch_completed_queues(db, date_range: DateRange) -> list[QueueActivity]:
    query = (
        db.collection("queues")
        .where(filter=FieldFilter("status", "==", "completed"))
        .where(filter=FieldFilter("completedAt", ">=", date_range.start))
        .where(filter=FieldFilter("completedAt", "<", date_range.end))
    )

    activities = []
    try:
        for doc in query.stream():
            activity = normalize_queue_doc(doc)
            if activity:
                activities.append(activity)
    except Exception as exc:
        LOGGER.exception(
            "Report query failed: collection=queues query=status_completed_completedAt_range exceptionType=%s",
            type(exc).__name__,
        )
        raise

    activities.sort(key=lambda item: item.completed_at)
    return activities


def normalize_study_session(doc) -> StudySession | None:
    try:
        data = doc.to_dict() or {}
    except Exception as exc:
        LOGGER.exception(
            "Failed to read report document: collection=studySessions docId=%s type=%s",
            getattr(doc, "id", "unknown"),
            type(exc).__name__,
        )
        return None

    started_at = (
        _scheduled_datetime(data.get("slotDate"), data.get("slotStart"))
        or _to_datetime(data.get("startedAt") or data.get("createdAt"))
    )
    if started_at is None:
        _log_skip("studySessions", doc.id, "missing_startedAt")
        return None

    return StudySession(
        session_id=doc.id,
        started_at=started_at,
        ended_at=(
            _scheduled_datetime(data.get("slotDate"), data.get("slotEnd"))
            or _to_datetime(data.get("endedAt") or data.get("updatedAt"))
        ),
        student_count=max(_safe_int(data.get("studentCount"), 0), 0),
        duty_teacher_name=_clean(
            data.get("completedDutyTeacherName")
            or data.get("dutyTeacherName")
            or data.get("branchTeacherName")
            or data.get("teacherName")
        )
        or None,
        duty_teacher_id=_clean(
            data.get("completedDutyTeacherId")
            or data.get("dutyTeacherId")
            or data.get("branchTeacherId")
            or data.get("teacherId")
        )
        or None,
    )


def _hydrate_study_session_teacher_names(db, sessions: list[StudySession]) -> None:
    teacher_ids = sorted(
        {
            session.duty_teacher_id
            for session in sessions
            if session.duty_teacher_id and not session.duty_teacher_name
        }
    )
    if not teacher_ids:
        return

    teacher_names = {}
    for teacher_id in teacher_ids:
        try:
            teacher_doc = db.collection("users").document(teacher_id).get()
            if teacher_doc.exists:
                teacher_names[teacher_id] = _teacher_name_from_data(
                    teacher_doc.to_dict() or {}
                )
        except Exception as exc:
            LOGGER.warning(
                "Failed to resolve study session duty teacher: teacherId=%s exceptionType=%s",
                teacher_id,
                type(exc).__name__,
            )

    for session in sessions:
        if not session.duty_teacher_name and session.duty_teacher_id:
            session.duty_teacher_name = teacher_names.get(session.duty_teacher_id) or None


def fetch_completed_study_sessions(db, date_range: DateRange) -> list[StudySession]:
    query = (
        db.collection("studySessions")
        .where(filter=FieldFilter("status", "==", "completed"))
        .where(filter=FieldFilter("startedAt", ">=", date_range.start))
        .where(filter=FieldFilter("startedAt", "<", date_range.end))
    )

    sessions = []
    try:
        for doc in query.stream():
            session = normalize_study_session(doc)
            if session:
                sessions.append(session)
    except Exception as exc:
        LOGGER.exception(
            "Report query failed: collection=studySessions query=status_completed_startedAt_range exceptionType=%s",
            type(exc).__name__,
        )
        raise

    sessions.sort(key=lambda item: item.started_at)
    _hydrate_study_session_teacher_names(db, sessions)
    return sessions


def fetch_study_attendances(
    db,
    sessions: Iterable[StudySession],
    date_range: DateRange,
) -> list[StudyAttendance]:
    session_map = {session.session_id: session for session in sessions}
    if not session_map:
        return []

    attendances = []
    query = (
        db.collection_group("students")
        .where(filter=FieldFilter("checkedAt", ">=", date_range.start))
        .where(filter=FieldFilter("checkedAt", "<", date_range.end))
    )

    try:
        for doc in query.stream():
            session_ref = doc.reference.parent.parent
            if session_ref is None or session_ref.id not in session_map:
                continue

            attendance = normalize_study_attendance(doc, session_map)
            if attendance:
                attendances.append(attendance)
    except Exception as exc:
        LOGGER.exception(
            "Report query failed: collection=studySessionStudents query=collectionGroup_checkedAt_range exceptionType=%s",
            type(exc).__name__,
        )
        raise

    attendances.sort(key=lambda item: (item.started_at, item.student_name))
    return attendances


def normalize_study_attendance(doc, session_map: dict[str, StudySession]) -> StudyAttendance | None:
    session_ref = doc.reference.parent.parent
    if session_ref is None or session_ref.id not in session_map:
        return None

    try:
        data = doc.to_dict() or {}
    except Exception as exc:
        LOGGER.exception(
            "Failed to read report document: collection=studySessionStudents docId=%s type=%s",
            getattr(doc, "id", "unknown"),
            type(exc).__name__,
        )
        return None

    try:
        status = _clean(data.get("status"), "present")
        if status not in {"present", "completed", "left"}:
            _log_skip("studySessionStudents", doc.id, f"unsupported_status_{status}")
            return None

        session = session_map[session_ref.id]
        checked_out_at = _to_datetime(data.get("checkedOutAt"))
        return StudyAttendance(
            student_id=_clean(data.get("studentId"), doc.id),
            student_name=_clean(
                data.get("studentName"),
                "Çıkarıldı" if status == "left" else "Öğrenci",
            ),
            session_id=session.session_id,
            started_at=session.started_at,
            ended_at=checked_out_at or session.ended_at,
            status=status,
        )
    except Exception as exc:
        LOGGER.exception(
            "Failed to normalize study attendance: collection=studySessionStudents docId=%s type=%s",
            doc.id,
            type(exc).__name__,
        )
        return None


def fetch_class_students(
    db,
    class_name: str,
    branch: str = "",
    department: str = "",
) -> list[StudentReportRow]:
    query = (
        db.collection("users")
        .where(filter=FieldFilter("role", "==", "student"))
        .where(filter=FieldFilter("className", "==", class_name))
    )

    students = []
    try:
        for doc in query.stream():
            data = doc.to_dict() or {}
            student_branch = _clean(data.get("branch"))
            student_department = _clean(data.get("department"))
            if branch and student_branch != branch:
                continue
            if department and student_department != department:
                continue

            students.append(
                StudentReportRow(
                    student_id=doc.id,
                    student_name=_clean(
                        data.get("fullName") or data.get("name"),
                        "Öğrenci",
                    ),
                    class_name=_clean(data.get("className")),
                    branch=student_branch,
                    department=student_department,
                )
            )
    except Exception as exc:
        LOGGER.exception(
            "Report query failed: collection=users query=student_className exceptionType=%s",
            type(exc).__name__,
        )
        raise

    students.sort(key=lambda item: item.student_name.casefold())
    return students


def build_institution_summary(start_date: str, end_date: str) -> InstitutionSummaryData:
    db = firestore.client()
    date_range = parse_date_range(start_date, end_date)
    queues = fetch_completed_queues(db, date_range)
    sessions = fetch_completed_study_sessions(db, date_range)
    attendances = fetch_study_attendances(db, sessions, date_range)

    return InstitutionSummaryData(
        date_range=date_range,
        completed_questions=queues,
        study_sessions=sessions,
        study_attendances=attendances,
    )


def build_class_report(
    class_name: str,
    start_date: str,
    end_date: str,
    branch: str | None = None,
    department: str | None = None,
) -> ClassReportData:
    db = firestore.client()
    clean_class_name = _clean(class_name)
    if not clean_class_name:
        raise ValueError("Sınıf seçimi zorunludur.")

    clean_branch = _clean(branch)
    clean_department = _clean(department)

    date_range = parse_date_range(start_date, end_date)
    students = fetch_class_students(
        db,
        clean_class_name,
        branch=clean_branch,
        department=clean_department,
    )
    if students:
        student_branches = {student.branch for student in students if student.branch}
        student_departments = {
            student.department for student in students if student.department
        }
        if not clean_branch and len(student_branches) == 1:
            clean_branch = next(iter(student_branches))
        if not clean_department and len(student_departments) == 1:
            clean_department = next(iter(student_departments))

    report_class_name = "-".join(
        value
        for value in [clean_class_name, clean_branch, clean_department]
        if value
    )
    student_map = {student.student_id: student for student in students}
    queues = fetch_completed_queues(db, date_range)
    sessions = fetch_completed_study_sessions(db, date_range)
    attendances = fetch_study_attendances(db, sessions, date_range)

    for queue in queues:
        student = student_map.get(queue.student_id)
        if not student:
            continue

        student.question_timeline.append(queue)
        student.questions_by_subject[queue.subject] = (
            student.questions_by_subject.get(queue.subject, 0) + 1
        )

    for attendance in attendances:
        student = student_map.get(attendance.student_id)
        if student:
            student.study_attendances.append(attendance)

    for student in students:
        student.question_timeline.sort(key=lambda item: item.completed_at)
        student.study_attendances.sort(key=lambda item: item.started_at)

    return ClassReportData(
        class_name=report_class_name,
        date_range=date_range,
        students=students,
    )
