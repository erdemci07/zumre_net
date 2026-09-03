from __future__ import annotations

import logging
from datetime import datetime
from typing import Callable

import firebase_admin
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from pydantic import BaseModel, Field

from auth import require_admin
from firestore_queries import build_class_report, build_institution_summary
from reports import class_activity, class_tracking, institution_summary


if not firebase_admin._apps:
    firebase_admin.initialize_app()


app = FastAPI(title="ZümreNet Reports")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


class ReportRequest(BaseModel):
    start_date: str = Field(alias="startDate")
    end_date: str = Field(alias="endDate")
    class_name: str | None = Field(default=None, alias="className")
    branch: str | None = None
    department: str | None = None


def _safe_filename(value: str) -> str:
    replacements = {
        "ı": "i",
        "İ": "I",
        "ş": "s",
        "Ş": "S",
        "ğ": "g",
        "Ğ": "G",
        "ü": "u",
        "Ü": "U",
        "ö": "o",
        "Ö": "O",
        "ç": "c",
        "Ç": "C",
    }
    text = "".join(replacements.get(char, char) for char in value)
    return "".join(char if char.isalnum() or char in {"-", "_"} else "_" for char in text)


def _pdf_response(content: bytes, filename: str) -> Response:
    return Response(
        content=content,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


def _build_pdf(
    request: ReportRequest,
    renderer: Callable,
    report_name: str,
    class_required: bool = False,
) -> Response:
    try:
        if class_required:
            if not request.class_name or not request.class_name.strip():
                raise ValueError("Sınıf seçimi zorunludur.")
            data = build_class_report(
                request.class_name.strip(),
                request.start_date,
                request.end_date,
                branch=request.branch,
                department=request.department,
            )
        else:
            data = build_institution_summary(request.start_date, request.end_date)

        pdf_bytes = renderer.render(data)
        class_label = data.class_name if class_required else ""
        class_part = f"{_safe_filename(class_label)}_" if class_required else ""
        filename = (
            f"{class_part}{report_name}_{request.start_date}_{request.end_date}.pdf"
        )
        return _pdf_response(pdf_bytes, filename)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        logging.exception(
            "Report generation failed: reportType=%s startDate=%s endDate=%s className=%s exceptionType=%s",
            report_name,
            request.start_date,
            request.end_date,
            request.class_name or "",
            type(exc).__name__,
        )
        raise HTTPException(
            status_code=500,
            detail="Rapor oluşturulamadı.",
        ) from exc


@app.get("/health")
def health():
    return {"ok": True, "time": datetime.utcnow().isoformat()}


@app.post("/reports/institution-summary")
def institution_summary_report(
    request: ReportRequest,
    _: dict = Depends(require_admin),
):
    return _build_pdf(request, institution_summary, "Kurum_Faaliyet_Ozeti")


@app.post("/reports/class-tracking")
def class_tracking_report(
    request: ReportRequest,
    _: dict = Depends(require_admin),
):
    return _build_pdf(
        request,
        class_tracking,
        "Sinif_Takip_Raporu",
        class_required=True,
    )


@app.post("/reports/class-activity")
def class_activity_report(
    request: ReportRequest,
    _: dict = Depends(require_admin),
):
    return _build_pdf(
        request,
        class_activity,
        "Sinif_Faaliyet_Takip_Raporu",
        class_required=True,
    )
