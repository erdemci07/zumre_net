from __future__ import annotations

import re
from io import BytesIO

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

from models import ClassReportData
from pdf.components import empty_state, footer, generated_at_label, range_label, report_header, simple_table
from pdf.styles import report_styles
from report_metrics import class_activity_summary


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
    summary = class_activity_summary(data)
    total = sum(item["question_count"] for item in summary)
    story = [report_header(f"{_display_class_name(data.class_name)} SINIF FAALİYET ÖZETİ", range_label(data.date_range.start, data.date_range.end), styles)]

    if not data.students:
        story.append(empty_state("Seçilen sınıfta öğrenci bulunamadı.", styles))
    elif not summary:
        story.append(empty_state("Seçilen tarih aralığında tamamlanan soru kaydı yok.", styles))
    else:
        rows = [[item["subject"], f"{item['question_count']} soru", ", ".join(item["teacher_names"]) or "-"] for item in summary]
        story.append(simple_table(["Ders", "Tamamlanan soru", "Öğretmen"], rows, [52 * mm, 45 * mm, 73 * mm], font_size=9))
        story.extend([Spacer(1, 12), Paragraph(f"Toplam tamamlanan soru: <b>{total}</b>", styles["section"])])

    story.append(Spacer(1, 12))
    story.append(Paragraph(f"Rapor oluşturma: {generated_at_label()}", styles["small"]))
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    return buffer.getvalue()
