from __future__ import annotations

from datetime import datetime
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)

from .styles import FONT_BOLD, FONT_REGULAR, LINE, MUTED, NAVY, SOFT, TEXT
from .styles import BLUE, CYAN, SOFT_ALT, TEAL, WHITE


MONTHS = [
    "Ocak",
    "Şubat",
    "Mart",
    "Nisan",
    "Mayıs",
    "Haziran",
    "Temmuz",
    "Ağustos",
    "Eylül",
    "Ekim",
    "Kasım",
    "Aralık",
]


def escape(value) -> str:
    return str(value or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def date_label(value: datetime) -> str:
    return f"{value.day:02d} {MONTHS[value.month - 1]} {value.year}"


def short_date(value: datetime) -> str:
    return f"{value.day:02d} {MONTHS[value.month - 1][:3]}"


def time_label(value: datetime | None) -> str:
    if value is None:
        return "-"
    return f"{value.hour:02d}:{value.minute:02d}"


def range_label(start: datetime, end_exclusive: datetime) -> str:
    visible_end = end_exclusive
    if visible_end.hour == 0 and visible_end.minute == 0:
        from datetime import timedelta

        visible_end = visible_end - timedelta(days=1)

    if start.date() == visible_end.date():
        return date_label(start)

    return f"{date_label(start)} - {date_label(visible_end)}"


def report_header(title: str, date_text: str, styles):
    return KeepTogether(
        [
            Paragraph("BİLİM KALESİ EĞİTİM KURUMLARI", styles["institution"]),
            Paragraph(title, styles["title"]),
            Paragraph(date_text, styles["date"]),
            Spacer(1, 6),
            Table(
                [[""]],
                colWidths=[170 * mm],
                rowHeights=[1.8],
                style=TableStyle([("BACKGROUND", (0, 0), (-1, -1), CYAN)]),
            ),
            Spacer(1, 12),
        ]
    )


def section(title: str, first_block, styles):
    return KeepTogether([Paragraph(title, styles["section"]), first_block])


def metric_grid(metrics, styles):
    cells = []
    for value, label in metrics:
        cell = Table(
            [
                [""],
                [Paragraph(str(value), styles["metric_value"])],
                [Paragraph(escape(label), styles["metric_label"])],
            ],
            colWidths=[36 * mm],
            rowHeights=[2, None, None],
        )
        cell.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), CYAN),
                    ("BACKGROUND", (0, 1), (-1, -1), SOFT),
                    ("BOX", (0, 0), (-1, -1), 0.45, LINE),
                    ("TOPPADDING", (0, 1), (-1, -1), 7),
                    ("BOTTOMPADDING", (0, 1), (-1, -1), 7),
                ]
            )
        )
        cells.append(cell)

    table = Table(
        [cells],
        colWidths=[42 * mm] * len(cells),
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), colors.white),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.white),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
            ]
        )
    )
    return table


def simple_table(headers, rows, col_widths=None, font_size=8):
    header_style = ParagraphStyle(
        "table_header",
        fontName=FONT_BOLD,
        fontSize=font_size,
        leading=font_size + 2,
        textColor=WHITE,
    )
    body_style = ParagraphStyle(
        "table_body",
        fontName=FONT_REGULAR,
        fontSize=font_size,
        leading=font_size + 2.2,
        textColor=TEXT,
    )
    prepared_rows = [
        [Paragraph(escape(cell), header_style) for cell in headers],
        *[
            [
                cell
                if isinstance(cell, Paragraph)
                else Paragraph(escape(cell), body_style)
                for cell in row
            ]
            for row in rows
        ],
    ]
    table = Table(
        prepared_rows,
        colWidths=col_widths,
        repeatRows=1,
        hAlign="LEFT",
    )
    table.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, 0), FONT_BOLD),
                ("FONTNAME", (0, 1), (-1, -1), FONT_REGULAR),
                ("FONTSIZE", (0, 0), (-1, -1), font_size),
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, SOFT_ALT]),
                ("GRID", (0, 0), (-1, -1), 0.35, LINE),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 5),
                ("RIGHTPADDING", (0, 0), (-1, -1), 5),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]
        )
    )
    return table


def highlight_grid(highlights, styles):
    cells = []
    for title, value, accent in highlights:
        cell = Table(
            [
                [""],
                [Paragraph(escape(title), styles["small"])],
                [Paragraph(escape(value), styles["body"])],
            ],
            colWidths=[80 * mm],
            rowHeights=[2, None, None],
        )
        cell.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), accent),
                    ("BACKGROUND", (0, 1), (-1, -1), SOFT),
                    ("BOX", (0, 0), (-1, -1), 0.45, LINE),
                    ("LEFTPADDING", (0, 1), (-1, -1), 9),
                    ("RIGHTPADDING", (0, 1), (-1, -1), 9),
                    ("TOPPADDING", (0, 1), (-1, -1), 7),
                    ("BOTTOMPADDING", (0, 1), (-1, -1), 7),
                ]
            )
        )
        cells.append(cell)

    return Table(
        [cells],
        colWidths=[84 * mm] * len(cells),
        hAlign="LEFT",
        style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]),
    )


def empty_state(message: str, styles):
    return Table(
        [[Paragraph(escape(message), styles["body"])]],
        colWidths=[170 * mm],
        style=TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, -1), SOFT),
                ("BOX", (0, 0), (-1, -1), 0.5, CYAN),
                ("TOPPADDING", (0, 0), (-1, -1), 8),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ]
        ),
    )


def footer(canvas, doc):
    page_width, _ = A4
    canvas.saveState()
    canvas.setFont(FONT_REGULAR, 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(doc.leftMargin, 12 * mm, "ZümreNet • Bilim Kalesi Eğitim Kurumları")
    canvas.drawRightString(page_width - doc.rightMargin, 12 * mm, f"Sayfa {doc.page}")
    canvas.restoreState()
