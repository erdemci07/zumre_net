from __future__ import annotations

from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

from models import ClassReportData, DateRange, InstitutionSummaryData, StudentReportRow
from pdf.pagination import student_chunks
from reports import class_activity, class_tracking, institution_summary
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


def test_student_chunks_adds_continuation_title_for_long_sections():
    styles = report_styles()
    blocks = [student_chunks.__globals__["Paragraph"](f"Satır {index}", styles["body"]) for index in range(25)]

    chunks = student_chunks("HASAN KAYA", blocks, styles, chunk_size=10)

    assert len(chunks) == 3
