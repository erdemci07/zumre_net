from __future__ import annotations

from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import SimpleDocTemplate

from models import ClassReportData
from pdf.components import (
    empty_state,
    footer,
    range_label,
    report_header,
    short_date,
    simple_table,
    time_label,
)
from pdf.styles import report_styles


def _student_activity_rows(data: ClassReportData):
    for student in sorted(data.students, key=lambda item: item.student_name.casefold()):
        activities = []
        for queue in student.question_timeline:
            activities.append(
                (
                    queue.completed_at,
                    short_date(queue.completed_at),
                    time_label(queue.completed_at),
                    f"{queue.subject} - 1 soru",
                )
            )
        for attendance in student.study_attendances:
            activities.append(
                (
                    attendance.started_at,
                    short_date(attendance.started_at),
                    f"{time_label(attendance.started_at)}-{time_label(attendance.ended_at)}",
                    "Etüt",
                )
            )

        activities.sort(key=lambda item: item[0])
        if not activities:
            yield [student.student_name, "-", "-", "Faaliyet yok"]
            continue

        for index, (_, date_text, time_text, detail) in enumerate(activities):
            yield [
                student.student_name if index == 0 else "",
                date_text,
                time_text,
                detail,
            ]


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
            f"{data.class_name} SINIF FAALİYET TAKİP RAPORU",
            range_label(data.date_range.start, data.date_range.end),
            styles,
        )
    ]

    if not data.students:
        story.append(empty_state("Seçilen sınıfta öğrenci bulunamadı.", styles))
    else:
        story.append(
            simple_table(
                ["Öğrenci", "Tarih", "Saat", "Faaliyet"],
                list(_student_activity_rows(data)),
                [45 * mm, 24 * mm, 30 * mm, 73 * mm],
                font_size=7.4,
            )
        )

    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
