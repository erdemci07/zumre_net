from __future__ import annotations

from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from pdf.components import empty_state, footer, generated_at_label, range_label, report_header, simple_table
from pdf.styles import report_styles


def render(data: dict) -> bytes:
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
    date_range = data["date_range"]
    level = data["education_level"]
    teachers = data["teachers"]

    story = [
        report_header(
            f"{level} ÖĞRETMEN FAALİYET ÖZETİ",
            range_label(date_range.start, date_range.end),
            styles,
        ),
        Spacer(1, 8),
    ]

    if not teachers:
        story.append(empty_state(f"{level} kapsamında öğretmen bulunamadı.", styles))
    else:
        rows = [
            [
                teacher["name"],
                teacher["subjects"] or "-",
                str(teacher["question_count"]),
            ]
            for teacher in teachers
        ]
        story.append(
            simple_table(
                ["Öğretmen", "Branş", "Zümrede Çözülen Soru"],
                rows,
                [65 * mm, 55 * mm, 50 * mm],
                font_size=8.5,
            )
        )
        story.append(Spacer(1, 8))
        story.append(
            Paragraph(
                "Faaliyeti olmayan öğretmenler de kapsam listesinde gösterilir. Zümre sütunu, tamamlanan soru sayısını gösterir.",
                styles["small"],
            )
        )

    story.append(Spacer(1, 12))
    story.append(Paragraph(f"Rapor oluşturma: {generated_at_label()}", styles["small"]))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
