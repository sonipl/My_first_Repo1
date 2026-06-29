from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class UserAccount(Base):
    __tablename__ = "user_accounts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    device_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    tesla_tokens: Mapped["TeslaToken | None"] = relationship(back_populates="user", uselist=False)
    vehicles: Mapped[list["Vehicle"]] = relationship(back_populates="user")
    daily_usage: Mapped[list["DailyUsage"]] = relationship(back_populates="user")


class TeslaToken(Base):
    __tablename__ = "tesla_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("user_accounts.id"), unique=True)
    access_token: Mapped[str] = mapped_column(Text)
    refresh_token: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user: Mapped["UserAccount"] = relationship(back_populates="tesla_tokens")


class Vehicle(Base):
    __tablename__ = "vehicles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("user_accounts.id"))
    vin: Mapped[str] = mapped_column(String(32), index=True)
    display_name: Mapped[str] = mapped_column(String(128), default="My Tesla")
    model: Mapped[str | None] = mapped_column(String(64), nullable=True)

    user: Mapped["UserAccount"] = relationship(back_populates="vehicles")
    snapshots: Mapped[list["VehicleSnapshot"]] = relationship(back_populates="vehicle")
    daily_usage: Mapped[list["DailyUsage"]] = relationship(back_populates="vehicle")

    __table_args__ = (UniqueConstraint("user_id", "vin", name="uq_user_vin"),)


class VehicleSnapshot(Base):
    """Point-in-time reading from Tesla API."""

    __tablename__ = "vehicle_snapshots"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    vehicle_id: Mapped[int] = mapped_column(ForeignKey("vehicles.id"), index=True)
    captured_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)

    odometer_miles: Mapped[float | None] = mapped_column(Float, nullable=True)
    battery_percent: Mapped[float | None] = mapped_column(Float, nullable=True)
    est_range_miles: Mapped[float | None] = mapped_column(Float, nullable=True)
    charge_energy_added_kwh: Mapped[float | None] = mapped_column(Float, nullable=True)
    charge_rate_mph: Mapped[float | None] = mapped_column(Float, nullable=True)
    charging_state: Mapped[str | None] = mapped_column(String(32), nullable=True)
    is_climate_on: Mapped[bool | None] = mapped_column(nullable=True)
    sentry_mode: Mapped[bool | None] = mapped_column(nullable=True)
    raw_json: Mapped[str | None] = mapped_column(Text, nullable=True)

    vehicle: Mapped["Vehicle"] = relationship(back_populates="snapshots")


class DailyUsage(Base):
    """Aggregated daily usage derived from snapshots."""

    __tablename__ = "daily_usage"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("user_accounts.id"), index=True)
    vehicle_id: Mapped[int] = mapped_column(ForeignKey("vehicles.id"), index=True)
    usage_date: Mapped[date] = mapped_column(Date, index=True)

    miles_driven: Mapped[float] = mapped_column(Float, default=0.0)
    energy_charged_kwh: Mapped[float] = mapped_column(Float, default=0.0)
    start_odometer_miles: Mapped[float | None] = mapped_column(Float, nullable=True)
    end_odometer_miles: Mapped[float | None] = mapped_column(Float, nullable=True)
    start_battery_percent: Mapped[float | None] = mapped_column(Float, nullable=True)
    end_battery_percent: Mapped[float | None] = mapped_column(Float, nullable=True)
    charging_sessions: Mapped[int] = mapped_column(Integer, default=0)
    snapshot_count: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user: Mapped["UserAccount"] = relationship(back_populates="daily_usage")
    vehicle: Mapped["Vehicle"] = relationship(back_populates="daily_usage")

    __table_args__ = (UniqueConstraint("vehicle_id", "usage_date", name="uq_vehicle_date"),)
