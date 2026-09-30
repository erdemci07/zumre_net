from __future__ import annotations

import re
from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from models import ClassReportData
from pdf.components import empty_state, footer, generated_at_label, range_label, report_header, simple_table
from pdf.styles import report_styles


def _subject_summary(subjects: dict[str, int]) -> str:
    if not subjects:
        return "-"
    parts = [
        f"{subject} {count} soru"
        for subject, count in sorted(
            subjects.items(),
            key=lambda item: (-item[1], item[0]),
        )
    ]
    return " - ".join(parts)


def _student_summary_rows(data: ClassReportData):
    return [
        [
            student.student_name,
            _subject_summary(student.questions_by_subject),
            str(student.completed_questions),
            str(len(student.study_attendances)),
        ]
        for student in sorted(
            data.students,
            key=lambda item: item.student_name.casefold(),
        )
    ]


def _display_class_name(value: str) -> str:
    """Keep legacy values intact unless the grade delimiter is unambiguous."""
    text = value.strip()
    match = re.match(r"^(5|6|7|8|9|10|11|12)-(.*)$", text, re.IGNORECASE)
    if match:
        return f"{match.group(1)}. Sınıf • {_display_detail(match.group(2))}"
    graduate = re.match(r"^MEZUN-(.*)$", text, re.IGNORECASE)
    if graduate:
        return f"Mezun • {_display_detail(graduate.group(1))}"
    return text


def _display_detail(value: str) -> str:
    detail = value.strip()
    upper = detail.upper()
    if upper.startswith("DERSLİK "):
        return f"Derslik{detail[7:]}"
    labels = {
        "HAFTA SONU ETÜT": "Hafta Sonu Etüt",
        "ÇALIŞMA SALONU": "Çalışma Salonu",
        "ETÜT": "Etüt",
    }
    return labels.get(upper, detail)


def render(data: ClassReportData) -> bytes:
    styles = report_styles()
    buffer = BytesIO()
    doc = SimpleDocTemplate(buffer, pagesize=A4, leftMargin=16 * mm, rightMargin=16 * mm, topMargin=15 * mm, bottomMargin=18 * mm)
    story = [report_header(f"{_display_class_name(data.class_name)} SINIF FAALİYET ÖZETİ", range_label(data.date_range.start, data.date_range.end), styles)]

    if not data.students:
        story.append(empty_state("Seçilen sınıfta öğrenci bulunamadı.", styles))
    else:
        story.append(
            simple_table(
                ["Öğrenci", "Zümre Özeti", "Toplam Soru", "Etüt"],
                _student_summary_rows(data),
                [45 * mm, 85 * mm, 24 * mm, 18 * mm],
                font_size=7.6,
            )
        )

    story.append(Spacer(1, 12))
    story.append(Paragraph(f"Rapor oluşturma: {generated_at_label()}", styles["small"]))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
