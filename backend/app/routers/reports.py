from fastapi import APIRouter, Depends, HTTPException, status, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from typing import Optional
from datetime import date
import uuid
import io

from ..database import get_db
from ..auth.security import get_current_active_user, log_system_activity
from ..models import User
from ..services.report_generation_service import ReportGenerationService
from ..services.pdf_report_generation_service import PdfReportGenerationService
from ..services.csv_report_generation_service import CsvReportGenerationService

router = APIRouter(
    prefix="/reports",
    tags=["reports"],
    responses={404: {"description": "Not found"}},
)


@router.get("/export-excel", response_class=StreamingResponse)
def export_excel_report(
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter for managers/admins."),
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD). Defaults to 30 days ago."),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD). Defaults to today."),
    report_type: Optional[str] = Query(None, description="Optional report type override."),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Export comprehensive multi-sheet Excel report (.xlsx) covering executive summary,
    productivity, work sessions, break analysis, wellbeing, and recommendation feedback.
    Enforces RBAC, profile isolation, and employee privacy thresholds.
    """
    service = ReportGenerationService(db)
    try:
        excel_bytes = service.generate_excel_report(
            current_user=current_user,
            team_id=team_id,
            start_date=start_date,
            end_date=end_date,
            report_type=report_type
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate Excel report: {str(e)}"
        )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="EXCEL_REPORT_EXPORTED",
        action_details={"team_id": str(team_id) if team_id else None, "start_date": str(start_date), "end_date": str(end_date), "report_type": report_type}
    )

    filename = f"intellibreak_report_{date.today()}.xlsx"
    return StreamingResponse(
        io.BytesIO(excel_bytes),
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@router.get("/export-pdf", response_class=StreamingResponse)
def export_pdf_report(
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter for managers/admins."),
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD). Defaults to 30 days ago."),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD). Defaults to today."),
    report_type: Optional[str] = Query(None, description="Optional report type override."),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Export professional PDF report covering executive summary, productivity,
    work sessions, break analysis, wellbeing, and recommendation effectiveness.
    Enforces RBAC, profile isolation, and employee privacy thresholds.
    """

    service = PdfReportGenerationService(db)
    try:
        pdf_bytes = service.generate_pdf_report(
            current_user=current_user,
            team_id=team_id,
            start_date=start_date,
            end_date=end_date,
            report_type=report_type
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate PDF report: {str(e)}"
        )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="PDF_REPORT_EXPORTED",
        action_details={"team_id": str(team_id) if team_id else None, "start_date": str(start_date), "end_date": str(end_date), "report_type": report_type}
    )

    filename = f"intellibreak_report_{date.today()}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )


@router.get("/export-csv", response_class=StreamingResponse)
def export_csv_report(
    team_id: Optional[uuid.UUID] = Query(None, description="Optional team filter for managers/admins."),
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD). Defaults to 30 days ago."),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD). Defaults to today."),
    report_type: Optional[str] = Query(None, description="Optional report type override."),
    current_user: User = Depends(get_current_active_user),
    db: Session = Depends(get_db),
):
    """
    Export multi-section CSV reports packaged as a ZIP archive (.zip) covering
    executive summary, productivity, work sessions, break analysis, wellbeing, and recommendations.
    Enforces RBAC, profile isolation, employee privacy thresholds, and formula injection safety.
    """
    service = CsvReportGenerationService(db)
    try:
        zip_bytes = service.generate_csv_zip(
            current_user=current_user,
            team_id=team_id,
            start_date=start_date,
            end_date=end_date,
            report_type=report_type
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to generate CSV export: {str(e)}"
        )

    log_system_activity(
        db=db,
        user_id=current_user.id,
        action_type="CSV_REPORT_EXPORTED",
        action_details={"team_id": str(team_id) if team_id else None, "start_date": str(start_date), "end_date": str(end_date), "report_type": report_type}
    )

    filename = f"intellibreak_reports_{date.today()}.zip"
    return StreamingResponse(
        io.BytesIO(zip_bytes),
        media_type="application/zip",
        headers={"Content-Disposition": f"attachment; filename={filename}"}
    )
