from __future__ import annotations

from collections import Counter, defaultdict

from models import ClassReportData, InstitutionSummaryData


def institution_metrics(data: InstitutionSummaryData):
    question_students = {item.student_id for item in data.completed_questions}
    study_students = {item.student_id for item in data.study_attendances}
    subject_counts = Counter(item.subject for item in data.completed_questions)
    study_slot_counts = defaultdict(int)

    for attendance in data.study_attendances:
        key = (
            f"{attendance.started_at.hour:02d}:{attendance.started_at.minute:02d}-"
            f"{attendance.ended_at.hour:02d}:{attendance.ended_at.minute:02d}"
            if attendance.ended_at
            else f"{attendance.started_at.hour:02d}:{attendance.started_at.minute:02d}-?"
        )
        study_slot_counts[key] += 1

    busiest_subject = subject_counts.most_common(1)[0] if subject_counts else None
    busiest_study = (
        sorted(study_slot_counts.items(), key=lambda item: (-item[1], item[0]))[0]
        if study_slot_counts
        else None
    )

    return {
        "zumre_student_count": len(question_students),
        "completed_question_count": len(data.completed_questions),
        "study_student_count": len(study_students),
        "completed_study_session_count": len(data.study_sessions),
        "subject_counts": dict(subject_counts),
        "busiest_subject": busiest_subject,
        "busiest_study": busiest_study,
    }


def class_totals(data: ClassReportData):
    return {
        "student_count": len(data.students),
        "question_count": sum(student.completed_questions for student in data.students),
        "study_attendance_count": sum(
            len(student.study_attendances) for student in data.students
        ),
    }


def class_activity_summary(data: ClassReportData):
    """Return only class-level, share-safe completed-question aggregates."""
    subjects = defaultdict(lambda: {"question_count": 0, "teacher_names": set()})
    for student in data.students:
        for queue in student.question_timeline:
            item = subjects[queue.subject]
            item["question_count"] += 1
            if queue.teacher_name:
                item["teacher_names"].add(queue.teacher_name)

    return [
        {
            "subject": subject,
            "question_count": values["question_count"],
            "teacher_names": sorted(values["teacher_names"], key=str.casefold),
        }
        for subject, values in sorted(
            subjects.items(), key=lambda item: (-item[1]["question_count"], item[0])
        )
    ]
