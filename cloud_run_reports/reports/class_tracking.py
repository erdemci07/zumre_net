from __future__ import annotations

from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from models import ClassReportData
from pdf.components import (
    empty_state,
    footer,
    generated_at_label,
    range_label,
    report_header,
    simple_table,
)
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


def render(data: ClassReportData) -> bytes:
    styles = report_styles()
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=16 * mm,
        rightMargin=16 * mm,
        topMargin=15 * mm,
        bottomMargin=18 * mm,
    )

    story = [
        report_header(
            f"{data.class_name} SINIF TAKİP RAPORU",
            range_label(data.date_range.start, data.date_range.end),
            styles,
        )
    ]

    if not data.students:
        story.append(empty_state("Seçilen sınıfta öğrenci bulunamadı.", styles))
    else:
        rows = [
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
        story.append(
            simple_table(
                ["Öğrenci", "Zümre Özeti", "Toplam Soru", "Etüt"],
                rows,
                [45 * mm, 85 * mm, 24 * mm, 18 * mm],
                font_size=7.6,
            )
        )

    story.append(Spacer(1, 12))
    story.append(
        Paragraph(
            f"Rapor oluşturma: {generated_at_label()}",
            styles["small"],
        )
    )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
