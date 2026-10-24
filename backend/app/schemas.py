from datetime import datetime
from typing import Optional
from pydantic import BaseModel, ConfigDict


class OutbreakSnapshotBase(BaseModel):
    source: str
    source_id: str

    country: Optional[str] = None
    state: Optional[str] = None
    county: Optional[str] = None
    city: Optional[str] = None
    site: Optional[str] = None

    region_type: Optional[str] = None
    region_code: Optional[str] = None
    region: Optional[str] = None  # legacy field

    condition_name: Optional[str] = None
    case_count: Optional[int] = None  # legacy field; prefer metric_value for new data
    weekly_count: Optional[int] = None  # current-week new cases (e.g., CDC NNDSS m1)
    metric_name: Optional[str] = None
    metric_value: Optional[float] = None
    metric_value_text: Optional[str] = None

    report_date: Optional[datetime] = None
    metadata_json: Optional[dict] = None


class OutbreakSnapshotCreate(OutbreakSnapshotBase):
    pass


class OutbreakSnapshotResponse(OutbreakSnapshotBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    updated_at: datetime
    created_at: datetime


class CommunitySignalBase(BaseModel):
    anonymous_id: str

    country: Optional[str] = None
    state: Optional[str] = None
    county: Optional[str] = None
    city: Optional[str] = None
    site: Optional[str] = None

    region_type: Optional[str] = None
    region_code: Optional[str] = None
    region: Optional[str] = None  # legacy field

    symptom_summary: Optional[str] = None
    risk_level: Optional[str] = None
    metadata_json: Optional[dict] = None


class CommunitySignalCreate(CommunitySignalBase):
    pass


class CommunitySignalResponse(CommunitySignalBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
    reported_at: datetime


class HeartbeatRequest(BaseModel):
    token: str


class OnlineCountResponse(BaseModel):
    count: int
    window_minutes: int
