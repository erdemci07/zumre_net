from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from firestore_queries import (
    _hydrate_queue_teacher_names,
    normalize_queue_doc,
    normalize_study_session,
)
from models import QueueActivity


ISTANBUL = ZoneInfo("Europe/Istanbul")


class FakeDoc:
    def __init__(self, doc_id: str, data: dict):
        self.id = doc_id
        self._data = data
        self.exists = True

    def to_dict(self):
        return self._data

    def get(self):
        return self


class FakeUsers:
    def __init__(self, users: dict):
        self._users = users

    def document(self, user_id):
        return FakeDoc(user_id, self._users.get(user_id, {}))


class FakeDb:
    def __init__(self, users: dict):
        self._users = users

    def collection(self, name):
        assert name == "users"
        return FakeUsers(self._users)


def test_legacy_negative_study_count_is_clamped_and_missing_duty_teacher_is_empty():
    session = normalize_study_session(
        FakeDoc(
            "legacy-study",
            {
                "startedAt": datetime(2026, 7, 12, 11, 12, tzinfo=ISTANBUL),
                "endedAt": datetime(2026, 7, 12, 11, 15, tzinfo=ISTANBUL),
                "studentCount": "-1",
                "dutyTeacherName": None,
            },
        )
    )

    assert session is not None
    assert session.student_count == 0
    assert session.duty_teacher_name is None


def test_bad_completed_queue_without_date_is_skipped_without_crash():
    assert normalize_queue_doc(
        FakeDoc(
            "legacy-queue",
            {
                "status": "completed",
                "studentName": "HASAN KAYA",
                "subject": "MATEMATİK",
            },
        )
    ) is None


def test_queue_teacher_id_is_resolved_only_to_an_actual_teacher():
    queue = QueueActivity(
        "student-1",
        "HASAN KAYA",
        "Matematik",
        datetime(2026, 7, 12, 11, 12, tzinfo=ISTANBUL),
        teacher_id="teacher-1",
    )
    legacy_queue = QueueActivity(
        "student-2",
        "AYŞE KAYA",
        "Matematik",
        datetime(2026, 7, 12, 11, 12, tzinfo=ISTANBUL),
        teacher_id="not-a-teacher",
    )

    _hydrate_queue_teacher_names(
        FakeDb({
            "teacher-1": {"role": "teacher", "fullName": "Ahmet Yılmaz"},
            "not-a-teacher": {"role": "student", "fullName": "Yanlış Eşleşme"},
        }),
        [queue, legacy_queue],
    )

    assert queue.teacher_name == "Ahmet Yılmaz"
    assert legacy_queue.teacher_name is None
