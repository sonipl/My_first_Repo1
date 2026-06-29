"""Daily usage agent — aggregates vehicle snapshots into daily reports."""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta

from sqlalchemy.orm import Session

from app.models import DailyUsage, UserAccount, Vehicle, VehicleSnapshot
from app.tesla_client import TeslaClient, TeslaAPIError

logger = logging.getLogger(__name__)


def _day_bounds(target: date) -> tuple[datetime, datetime]:
    start = datetime.combine(target, datetime.min.time())
    end = start + timedelta(days=1)
    return start, end


def aggregate_daily_usage(db: Session, vehicle: Vehicle, target: date) -> DailyUsage | None:
    start, end = _day_bounds(target)
    snapshots = (
        db.query(VehicleSnapshot)
        .filter(
            VehicleSnapshot.vehicle_id == vehicle.id,
            VehicleSnapshot.captured_at >= start,
            VehicleSnapshot.captured_at < end,
        )
        .order_by(VehicleSnapshot.captured_at.asc())
        .all()
    )

    if not snapshots:
        return None

    first, last = snapshots[0], snapshots[-1]
    miles_driven = 0.0
    if first.odometer_miles is not None and last.odometer_miles is not None:
        miles_driven = max(0.0, last.odometer_miles - first.odometer_miles)

    energy_charged = 0.0
    charging_sessions = 0
    prev_charging = False
    prev_energy = first.charge_energy_added_kwh or 0.0

    for snap in snapshots:
        energy = snap.charge_energy_added_kwh or 0.0
        if energy > prev_energy:
            energy_charged += energy - prev_energy
        prev_energy = energy

        is_charging = (snap.charging_state or "").lower() in {"charging", "starting"}
        if is_charging and not prev_charging:
            charging_sessions += 1
        prev_charging = is_charging

    record = (
        db.query(DailyUsage)
        .filter(DailyUsage.vehicle_id == vehicle.id, DailyUsage.usage_date == target)
        .first()
    )
    if not record:
        record = DailyUsage(
            user_id=vehicle.user_id,
            vehicle_id=vehicle.id,
            usage_date=target,
        )
        db.add(record)

    record.miles_driven = round(miles_driven, 2)
    record.energy_charged_kwh = round(energy_charged, 2)
    record.start_odometer_miles = first.odometer_miles
    record.end_odometer_miles = last.odometer_miles
    record.start_battery_percent = first.battery_percent
    record.end_battery_percent = last.battery_percent
    record.charging_sessions = charging_sessions
    record.snapshot_count = len(snapshots)
    record.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(record)
    return record


async def run_daily_agent(db: Session, target: date | None = None) -> dict:
    """Capture snapshots for all connected users and/wake vehicles and aggregate usage."""
    target = target or date.today()
    users = db.query(UserAccount).all()
    summary = {"users": len(users), "snapshots": 0, "daily_records": 0, "errors": []}

    for user in users:
        client = TeslaClient(db, user.id)
        if not client.is_connected:
            continue

        try:
            vehicles = await client.sync_vehicles()
        except TeslaAPIError as exc:
            summary["errors"].append({"user_id": user.id, "step": "sync", "error": str(exc)})
            continue

        for vehicle in vehicles:
            try:
                snapshot = await client.capture_snapshot(vehicle)
                summary["snapshots"] += 1
            except TeslaAPIError as exc:
                summary["errors"].append(
                    {"user_id": user.id, "vin": vehicle.vin, "step": "snapshot", "error": str(exc)}
                )
                continue

            record = aggregate_daily_usage(db, vehicle, target)
            if record:
                summary["daily_records"] += 1

    logger.info("Daily agent finished: %s", summary)
    return summary


def get_usage_history(db: Session, vehicle_id: int, days: int = 30) -> list[DailyUsage]:
    cutoff = date.today() - timedelta(days=days)
    return (
        db.query(DailyUsage)
        .filter(DailyUsage.vehicle_id == vehicle_id, DailyUsage.usage_date >= cutoff)
        .order_by(DailyUsage.usage_date.desc())
        .all()
    )
