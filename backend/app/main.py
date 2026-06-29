from __future__ import annotations

import secrets
from datetime import date, datetime

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.config import settings
from app.daily_agent import aggregate_daily_usage, get_usage_history, run_daily_agent
from app.database import Base, engine, get_db
from app.models import DailyUsage, UserAccount, Vehicle, VehicleSnapshot
from app.scheduler import start_scheduler
from app.tesla_client import TeslaAPIError, TeslaClient

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Tesla Daily Usage Agent", version="1.0.0")


@app.on_event("startup")
def on_startup():
    start_scheduler()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# --- Schemas ---


class RegisterResponse(BaseModel):
    device_id: str
    api_token: str


class ConnectRefreshRequest(BaseModel):
    refresh_token: str


class VehicleOut(BaseModel):
    id: int
    vin: str
    display_name: str
    model: str | None

    class Config:
        from_attributes = True


class DailyUsageOut(BaseModel):
    usage_date: date
    miles_driven: float
    energy_charged_kwh: float
    start_odometer_miles: float | None
    end_odometer_miles: float | None
    start_battery_percent: float | None
    end_battery_percent: float | None
    charging_sessions: int
    snapshot_count: int

    class Config:
        from_attributes = True


class TodaySummary(BaseModel):
    vehicle: VehicleOut
    today: DailyUsageOut | None
    latest_battery_percent: float | None
    latest_odometer_miles: float | None
    connected: bool


class StatusResponse(BaseModel):
    connected: bool
    vehicles: list[VehicleOut]
    next_snapshot: str


# --- Auth helpers ---

_pending_oauth: dict[str, int] = {}


def _resolve_user(db: Session, device_id: str | None, authorization: str | None) -> UserAccount:
    if not device_id:
        raise HTTPException(status_code=401, detail="X-Device-Id header required")

    user = db.query(UserAccount).filter(UserAccount.device_id == device_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="Device not registered. POST /devices/register first.")

    if authorization:
        token = authorization.removeprefix("Bearer ").strip()
        expected = f"{settings.app_secret_key}:{device_id}"
        if token != expected:
            raise HTTPException(status_code=403, detail="Invalid API token")

    return user


# --- Routes ---


@app.get("/health")
def health():
    return {"status": "ok", "service": "tesla-daily-usage-agent"}


@app.post("/devices/register", response_model=RegisterResponse)
def register_device(db: Session = Depends(get_db)):
    device_id = secrets.token_urlsafe(16)
    user = UserAccount(device_id=device_id)
    db.add(user)
    db.commit()
    api_token = f"{settings.app_secret_key}:{device_id}"
    return RegisterResponse(device_id=device_id, api_token=api_token)


@app.get("/auth/url")
def get_auth_url(
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
):
    user = _resolve_user(db, x_device_id, authorization)
    state = secrets.token_urlsafe(12)
    _pending_oauth[state] = user.id
    client = TeslaClient(db, user.id)
    return {"authorization_url": client.get_authorization_url(state)}


@app.get("/auth/callback")
async def auth_callback(code: str, state: str, db: Session = Depends(get_db)):
    user_id = _pending_oauth.pop(state, None)
    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid OAuth state")

    client = TeslaClient(db, user_id)
    try:
        await client.exchange_code(code)
        await client.sync_vehicles()
    except TeslaAPIError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"status": "connected", "message": "Tesla account linked. Return to the mobile app."}


@app.post("/auth/refresh-token")
async def connect_refresh_token(
    body: ConnectRefreshRequest,
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
):
    user = _resolve_user(db, x_device_id, authorization)
    client = TeslaClient(db, user.id)
    try:
        await client.connect_with_refresh_token(body.refresh_token)
        vehicles = await client.sync_vehicles()
    except TeslaAPIError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {"status": "connected", "vehicles": [VehicleOut.model_validate(v) for v in vehicles]}


@app.get("/status", response_model=StatusResponse)
def get_status(
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
):
    user = _resolve_user(db, x_device_id, authorization)
    client = TeslaClient(db, user.id)
    vehicles = db.query(Vehicle).filter(Vehicle.user_id == user.id).all()
    return StatusResponse(
        connected=client.is_connected,
        vehicles=[VehicleOut.model_validate(v) for v in vehicles],
        next_snapshot=f"{settings.daily_snapshot_hour:02d}:{settings.daily_snapshot_minute:02d} daily",
    )


@app.get("/usage/today", response_model=TodaySummary)
def get_today_usage(
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
    vehicle_id: int | None = Query(default=None),
):
    user = _resolve_user(db, x_device_id, authorization)
    client = TeslaClient(db, user.id)

    query = db.query(Vehicle).filter(Vehicle.user_id == user.id)
    vehicle = query.filter(Vehicle.id == vehicle_id).first() if vehicle_id else query.first()
    if not vehicle:
        raise HTTPException(status_code=404, detail="No vehicle found. Connect Tesla and sync first.")

    today_record = (
        db.query(DailyUsage)
        .filter(DailyUsage.vehicle_id == vehicle.id, DailyUsage.usage_date == date.today())
        .first()
    )

    latest_snapshot = (
        db.query(VehicleSnapshot)
        .filter(VehicleSnapshot.vehicle_id == vehicle.id)
        .order_by(VehicleSnapshot.captured_at.desc())
        .first()
    )

    return TodaySummary(
        vehicle=VehicleOut.model_validate(vehicle),
        today=DailyUsageOut.model_validate(today_record) if today_record else None,
        latest_battery_percent=latest_snapshot.battery_percent if latest_snapshot else None,
        latest_odometer_miles=latest_snapshot.odometer_miles if latest_snapshot else None,
        connected=client.is_connected,
    )


@app.get("/usage/history", response_model=list[DailyUsageOut])
def usage_history(
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
    vehicle_id: int = Query(...),
    days: int = Query(default=30, ge=1, le=365),
):
    user = _resolve_user(db, x_device_id, authorization)
    vehicle = (
        db.query(Vehicle)
        .filter(Vehicle.id == vehicle_id, Vehicle.user_id == user.id)
        .first()
    )
    if not vehicle:
        raise HTTPException(status_code=404, detail="Vehicle not found")

    records = get_usage_history(db, vehicle.id, days)
    return [DailyUsageOut.model_validate(r) for r in records]


@app.post("/agent/sync-now")
async def sync_now(
    db: Session = Depends(get_db),
    x_device_id: str | None = Header(default=None, alias="X-Device-Id"),
    authorization: str | None = Header(default=None),
):
    user = _resolve_user(db, x_device_id, authorization)
    client = TeslaClient(db, user.id)
    if not client.is_connected:
        raise HTTPException(status_code=400, detail="Tesla account not connected")

    vehicles = await client.sync_vehicles()
    results = []
    for vehicle in vehicles:
        try:
            snapshot = await client.capture_snapshot(vehicle)
            record = aggregate_daily_usage(db, vehicle, date.today())
            results.append(
                {
                    "vin": vehicle.vin,
                    "snapshot_id": snapshot.id,
                    "daily_usage": DailyUsageOut.model_validate(record).model_dump() if record else None,
                }
            )
        except TeslaAPIError as exc:
            results.append({"vin": vehicle.vin, "error": str(exc)})

    return {"synced_at": datetime.utcnow().isoformat(), "results": results}


@app.post("/agent/run-daily")
async def trigger_daily_agent(db: Session = Depends(get_db)):
    """Manual trigger for the scheduled daily agent (protect in production)."""
    return await run_daily_agent(db)
