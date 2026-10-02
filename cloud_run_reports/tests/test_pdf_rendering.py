from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from reportlab.platypus import Spacer

from models import ClassReportData, DateRange, InstitutionSummaryData, StudentReportRow
from pdf.pagination import student_chunks
from reports import class_activity, class_activity_summary, class_tracking, institution_summary, teacher_activity_summary
from reports.class_activity_summary import _student_summary_rows
from pdf.styles import report_styles


ISTANBUL = ZoneInfo("Europe/Istanbul")


def _range():
    start = datetime(2026, 9, 1, tzinfo=ISTANBUL)
    return DateRange(start, start + timedelta(days=1), "2026-09-01", "2026-09-01")


def test_reports_render_valid_pdf_bytes_without_firebase():
    empty_summary = InstitutionSummaryData(_range(), [], [], [])
    class_data = ClassReportData(
        "11-A",
        _range(),
        [StudentReportRow("s1", "HASAN KAYA", "11-A", "", "")],
    )

    assert institution_summary.render(empty_summary).startswith(b"%PDF")
    assert class_tracking.render(class_data).startswith(b"%PDF")
    assert class_activity.render(class_data).startswith(b"%PDF")
    assert class_activity_summary.render(class_data).startswith(b"%PDF")


def test_teacher_activity_summary_contains_no_study_session_column(monkeypatch):
    headers = []

    def capture_table(table_headers, rows, widths, font_size):
        headers.extend(table_headers)
        return Spacer(1, 1)

    monkeypatch.setattr(teacher_activity_summary, "simple_table", capture_table)
    data = {
        "education_level": "LGS",
        "date_range": _range(),
        "teachers": [
            {"name": "Öğretmen", "subjects": "Matematik", "question_count": 3}
        ],
    }

    assert teacher_activity_summary.render(data).startswith(b"%PDF")
    assert headers == ["Öğretmen", "Branş", "Zümrede Çözülen Soru"]


def test_student_chunks_adds_continuation_title_for_long_sections():
    styles = report_styles()
    blocks = [student_chunks.__globals__["Paragraph"](f"Satır {index}", styles["body"]) for index in range(25)]

    chunks = student_chunks("HASAN KAYA", blocks, styles, chunk_size=10)

    assert len(chunks) == 3


def test_class_activity_summary_keeps_students_without_activity():
    data = ClassReportData(
        "11-A",
        _range(),
        [StudentReportRow("s1", "Faaliyet Yok", "11-A", "", "")],
    )

    assert _student_summary_rows(data) == [["Faaliyet Yok", "-", "0", "0"]]
