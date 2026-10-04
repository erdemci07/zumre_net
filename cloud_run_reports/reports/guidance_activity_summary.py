from __future__ import annotations

from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from pdf.components import (
    empty_state,
    footer,
    generated_at_label,
    range_label,
    report_header,
    simple_table,
)
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
    counselors = data["counselors"]
    story = [
        report_header(
            "REHBERLİK FAALİYET ÖZETİ",
            range_label(data["date_range"].start, data["date_range"].end),
            styles,
        ),
        Spacer(1, 8),
    ]

    if not counselors:
        story.append(empty_state("Kurumda rehberlikçi bulunamadı.", styles))
    else:
        rows = [
            [
                counselor["name"],
                str(counselor["student_meeting_count"]),
                str(counselor["guardian_meeting_count"]),
                str(counselor["total_meeting_count"]),
            ]
            for counselor in counselors
        ]
        story.append(
            simple_table(
                ["Rehberlikçi", "Öğrenci Görüşmesi", "Veli Görüşmesi", "Toplam"],
                rows,
                [65 * mm, 43 * mm, 43 * mm, 24 * mm],
                font_size=8.5,
            )
        )
        story.append(Spacer(1, 8))
        story.append(
            Paragraph(
                "Yalnızca tamamlanan görüşmeler sayılır. Faaliyeti olmayan rehberlikçiler de 0 değerleriyle listelenir.",
                styles["small"],
            )
        )

    story.append(Spacer(1, 12))
    story.append(Paragraph(f"Rapor oluşturma: {generated_at_label()}", styles["small"]))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()