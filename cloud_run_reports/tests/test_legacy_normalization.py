from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from firestore_queries import normalize_queue_doc, normalize_study_session


ISTANBUL = ZoneInfo("Europe/Istanbul")


class FakeDoc:
    def __init__(self, doc_id: str, data: dict):
        self.id = doc_id
        self._data = data

    def to_dict(self):
        return self._data


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
