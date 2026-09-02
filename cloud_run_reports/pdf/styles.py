from __future__ import annotations

import os
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont


FONT_REGULAR = "Helvetica"
FONT_BOLD = "Helvetica-Bold"


def register_fonts() -> tuple[str, str]:
    global FONT_REGULAR, FONT_BOLD

    candidates = [
        (
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        ),
        (
            "C:/Windows/Fonts/arial.ttf",
            "C:/Windows/Fonts/arialbd.ttf",
        ),
    ]

    for regular_path, bold_path in candidates:
        if os.path.exists(regular_path) and os.path.exists(bold_path):
            pdfmetrics.registerFont(TTFont("ReportRegular", regular_path))
            pdfmetrics.registerFont(TTFont("ReportBold", bold_path))
            FONT_REGULAR = "ReportRegular"
            FONT_BOLD = "ReportBold"
            break

    return FONT_REGULAR, FONT_BOLD


NAVY = colors.HexColor("#10233F")
BLUE = colors.HexColor("#1864D9")
CYAN = colors.HexColor("#22B8CF")
TEAL = colors.HexColor("#0CA678")
TEXT = colors.HexColor("#222831")
MUTED = colors.HexColor("#5F6875")
LINE = colors.HexColor("#C9D8EA")
SOFT = colors.HexColor("#EFF6FF")
SOFT_ALT = colors.HexColor("#F8FBFF")
WHITE = colors.white


def report_styles():
    register_fonts()
    base = getSampleStyleSheet()

    return {
        "institution": ParagraphStyle(
            "institution",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=9,
            leading=11,
            textColor=MUTED,
            alignment=TA_LEFT,
        ),
        "title": ParagraphStyle(
            "title",
            parent=base["Title"],
            fontName=FONT_BOLD,
            fontSize=20,
            leading=24,
            textColor=NAVY,
            alignment=TA_LEFT,
            spaceAfter=4,
        ),
        "date": ParagraphStyle(
            "date",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=9.5,
            leading=12,
            textColor=MUTED,
        ),
        "section": ParagraphStyle(
            "section",
            parent=base["Heading2"],
            fontName=FONT_BOLD,
            fontSize=12.5,
            leading=15,
            textColor=BLUE,
            spaceBefore=6,
            spaceAfter=7,
            keepWithNext=True,
        ),
        "metric_value": ParagraphStyle(
            "metric_value",
            parent=base["Normal"],
            fontName=FONT_BOLD,
            fontSize=20,
            leading=23,
            textColor=NAVY,
            alignment=TA_CENTER,
        ),
        "metric_label": ParagraphStyle(
            "metric_label",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=8.5,
            leading=10,
            textColor=TEXT,
            alignment=TA_CENTER,
        ),
        "body": ParagraphStyle(
            "body",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=9,
            leading=12,
            textColor=TEXT,
        ),
        "small": ParagraphStyle(
            "small",
            parent=base["Normal"],
            fontName=FONT_REGULAR,
            fontSize=7.8,
            leading=9,
            textColor=MUTED,
        ),
        "student": ParagraphStyle(
            "student",
            parent=base["Heading3"],
            fontName=FONT_BOLD,
            fontSize=11,
            leading=14,
            textColor=NAVY,
            spaceBefore=4,
            spaceAfter=5,
            keepWithNext=True,
        ),
    }


register_fonts()
