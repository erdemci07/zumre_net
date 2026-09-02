from __future__ import annotations

from datetime import datetime
from io import BytesIO
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from models import InstitutionSummaryData
from pdf.components import (
    empty_state,
    footer,
    highlight_grid,
    metric_grid,
    range_label,
    report_header,
    section,
    simple_table,
    time_label,
)
from pdf.styles import report_styles
from pdf.styles import CYAN, TEAL
from report_metrics import institution_metrics


NO_DUTY_TEACHER_TEXT = "Bu oturumda branş öğretmeni seçilmedi."


def render(data: InstitutionSummaryData) -> bytes:
    styles = report_styles()
    metrics = institution_metrics(data)
    buffer = BytesIO()
    doc = SimpleDocTemplate(
        buffer,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=18 * mm,
    )

    story = [
        report_header(
            "KURUM FAALİYET ÖZETİ",
            range_label(data.date_range.start, data.date_range.end),
            styles,
        ),
    ]

    story.append(
        section(
            "GENEL METRİKLER",
            metric_grid(
                [
                    (metrics["zumre_student_count"], "Zümreden Yararlanan Öğrenci"),
                    (metrics["completed_question_count"], "Tamamlanan Zümre Sorusu"),
                    (metrics["study_student_count"], "Etüte Katılan Öğrenci"),
                    (
                        metrics["completed_study_session_count"],
                        "Tamamlanan Etüt Oturumu",
                    ),
                ],
                styles,
            ),
            styles,
        )
    )
    story.append(Spacer(1, 10))

    busiest_subject = metrics["busiest_subject"]
    busiest_study = metrics["busiest_study"]
    highlights = [
        (
            "En yoğun zümre",
            f"{busiest_subject[0]} - {busiest_subject[1]} soru"
            if busiest_subject
            else "Kayıt yok",
            CYAN,
        ),
        (
            "En yoğun etüt",
            f"{busiest_study[0]} - {busiest_study[1]} katılım"
            if busiest_study
            else "Kayıt yok",
            TEAL,
        ),
    ]
    story.append(section("ÖNE ÇIKANLAR", highlight_grid(highlights, styles), styles))
    story.append(Spacer(1, 10))

    subject_rows = [
        [str(index + 1), subject, str(count)]
        for index, (subject, count) in enumerate(
            sorted(
                metrics["subject_counts"].items(),
                key=lambda item: (-item[1], item[0]),
            )
        )
    ]
    story.append(
        section(
            "ZÜMRE YOĞUNLUĞU",
            simple_table(["#", "Ders", "Soru"], subject_rows, [12 * mm, 105 * mm, 30 * mm])
            if subject_rows
            else empty_state("Seçilen tarih aralığında tamamlanmış zümre sorusu bulunamadı.", styles),
            styles,
        )
    )
    story.append(Spacer(1, 10))

    if len(data.study_sessions) <= 7:
        study_rows = [
            [
                session.started_at.strftime("%d.%m.%Y"),
                f"{time_label(session.started_at)}-{time_label(session.ended_at)}",
                str(session.student_count),
                session.duty_teacher_name or NO_DUTY_TEACHER_TEXT,
            ]
            for session in data.study_sessions
        ]
        study_block = simple_table(
            ["Tarih", "Saat", "Öğrenci", "Branş Öğretmeni"],
            study_rows,
            [28 * mm, 30 * mm, 24 * mm, 78 * mm],
            font_size=7.8,
        ) if study_rows else empty_state("Seçilen tarih aralığında tamamlanmış etüt oturumu bulunamadı.", styles)
    else:
        totals = {}
        missing_teacher = 0
        for session in data.study_sessions:
            key = f"{time_label(session.started_at)}-{time_label(session.ended_at)}"
            totals[key] = totals.get(key, 0) + session.student_count
            if not session.duty_teacher_name:
                missing_teacher += 1
        rows = [[slot, str(count)] for slot, count in sorted(totals.items())]
        if missing_teacher:
            rows.append(["Branş öğretmeni seçilmeyen oturum", str(missing_teacher)])
        study_block = simple_table(["Saat Bandı", "Toplam Katılım"], rows, [90 * mm, 45 * mm])

    story.append(section("ETÜT OTURUMLARI", study_block, styles))
    story.append(Spacer(1, 12))
    story.append(
        Paragraph(
            f"Rapor oluşturma: {datetime.now().strftime('%d.%m.%Y %H:%M')}",
            styles["small"],
        )
    )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
