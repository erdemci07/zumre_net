from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any


@dataclass
class DateRange:
    start: datetime
    end: datetime
    start_label: str
    end_label: str


@dataclass
class QueueActivity:
    student_id: str
    student_name: str
    subject: str
    completed_at: datetime


@dataclass
class StudySession:
    session_id: str
    started_at: datetime
    ended_at: datetime | None
    student_count: int
    duty_teacher_name: str | None


@dataclass
class StudyAttendance:
    student_id: str
    student_name: str
    session_id: str
    started_at: datetime
    ended_at: datetime | None


@dataclass
class StudentReportRow:
    student_id: str
    student_name: str
    class_name: str
    branch: str
    department: str
    questions_by_subject: dict[str, int] = field(default_factory=dict)
    question_timeline: list[QueueActivity] = field(default_factory=list)
    study_attendances: list[StudyAttendance] = field(default_factory=list)

    @property
    def completed_questions(self) -> int:
        return len(self.question_timeline)


@dataclass
class InstitutionSummaryData:
    date_range: DateRange
    completed_questions: list[QueueActivity]
    study_sessions: list[StudySession]
    study_attendances: list[StudyAttendance]


@dataclass
class ClassReportData:
    class_name: str
    date_range: DateRange
    students: list[StudentReportRow]


JsonDict = dict[str, Any]
