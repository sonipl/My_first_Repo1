"""Tesla Fleet API client."""

from __future__ import annotations

from urllib.parse import urlencode

import httpx
from sqlalchemy.orm import Session

from app.config import settings
from app.models import TeslaToken, Vehicle, VehicleSnapshot


class TeslaAPIError(Exception):
    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


class TeslaClient:
    SCOPES = "openid offline_access vehicle_device_data vehicle_cmds vehicle_location"

    def __init__(self, db: Session, user_id: int):
        self.db = db
        self.user_id = user_id
        self._token: TeslaToken | None = (
            db.query(TeslaToken).filter(TeslaToken.user_id == user_id).first()
        )

    @property
    def is_connected(self) -> bool:
        return self._token is not None

    def get_authorization_url(self, state: str) -> str:
        params = {
            "client_id": settings.tesla_client_id,
            "redirect_uri": settings.tesla_redirect_uri,
            "response_type": "code",
            "scope": self.SCOPES,
            "state": state,
        }
        query = urlencode(params)
        return f"{settings.tesla_auth_url}/authorize?{query}"

    async def exchange_code(self, code: str) -> TeslaToken:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{settings.tesla_auth_url}/token",
                json={
                    "grant_type": "authorization_code",
                    "client_id": settings.tesla_client_id,
                    "client_secret": settings.tesla_client_secret,
                    "code": code,
                    "redirect_uri": settings.tesla_redirect_uri,
                    "audience": settings.tesla_fleet_api_url,
                },
            )
        if response.status_code >= 400:
            raise TeslaAPIError(f"Token exchange failed: {response.text}", response.status_code)

        data = response.json()
        return self._save_tokens(data)

    async def connect_with_refresh_token(self, refresh_token: str) -> TeslaToken:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.post(
                f"{settings.tesla_auth_url}/token",
                json={
                    "grant_type": "refresh_token",
                    "client_id": settings.tesla_client_id,
                    "client_secret": settings.tesla_client_secret,
                    "refresh_token": refresh_token,
                },
            )
        if response.status_code >= 400:
            raise TeslaAPIError(f"Refresh token invalid: {response.text}", response.status_code)

        data = response.json()
        data.setdefault("refresh_token", refresh_token)
        return self._save_tokens(data)

    def _save_tokens(self, data: dict[str, Any]) -> TeslaToken:
        expires_at = datetime.utcnow() + timedelta(seconds=int(data.get("expires_in", 3600)))
        if self._token:
            self._token.access_token = data["access_token"]
            self._token.refresh_token = data.get("refresh_token", self._token.refresh_token)
            self._token.expires_at = expires_at
        else:
            self._token = TeslaToken(
                user_id=self.user_id,
                access_token=data["access_token"],
                refresh_token=data["refresh_token"],
                expires_at=expires_at,
            )
            self.db.add(self._token)
        self.db.commit()
        self.db.refresh(self._token)
        return self._token

    async def _ensure_access_token(self) -> str:
        if not self._token:
            raise TeslaAPIError("Tesla account not connected")

        if self._token.expires_at <= datetime.utcnow() + timedelta(minutes=2):
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.post(
                    f"{settings.tesla_auth_url}/token",
                    json={
                        "grant_type": "refresh_token",
                        "client_id": settings.tesla_client_id,
                        "client_secret": settings.tesla_client_secret,
                        "refresh_token": self._token.refresh_token,
                    },
                )
            if response.status_code >= 400:
                raise TeslaAPIError("Failed to refresh Tesla token", response.status_code)
            data = response.json()
            data.setdefault("refresh_token", self._token.refresh_token)
            self._save_tokens(data)

        return self._token.access_token

    async def _request(self, method: str, path: str, **kwargs) -> dict[str, Any]:
        token = await self._ensure_access_token()
        headers = {"Authorization": f"Bearer {token}"}
        url = f"{settings.tesla_fleet_api_url}{path}"

        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.request(method, url, headers=headers, **kwargs)

        if response.status_code == 401:
            self._token.expires_at = datetime.utcnow()
            token = await self._ensure_access_token()
            headers = {"Authorization": f"Bearer {token}"}
            async with httpx.AsyncClient(timeout=60) as client:
                response = await client.request(method, url, headers=headers, **kwargs)

        if response.status_code >= 400:
            raise TeslaAPIError(f"Tesla API error: {response.text}", response.status_code)

        return response.json()

    async def list_vehicles(self) -> list[dict[str, Any]]:
        data = await self._request("GET", "/api/1/vehicles")
        return data.get("response", [])

    async def get_vehicle_data(self, vin: str) -> dict[str, Any]:
        data = await self._request("GET", f"/api/1/vehicles/{vin}/vehicle_data")
        return data.get("response", {})

    async def wake_vehicle(self, vin: str) -> dict[str, Any]:
        data = await self._request("POST", f"/api/1/vehicles/{vin}/wake_up")
        return data.get("response", {})

    async def sync_vehicles(self) -> list[Vehicle]:
        remote = await self.list_vehicles()
        synced: list[Vehicle] = []

        for item in remote:
            vin = item.get("vin")
            if not vin:
                continue
            vehicle = (
                self.db.query(Vehicle)
                .filter(Vehicle.user_id == self.user_id, Vehicle.vin == vin)
                .first()
            )
            if not vehicle:
                vehicle = Vehicle(user_id=self.user_id, vin=vin)
                self.db.add(vehicle)

            vehicle.display_name = item.get("display_name") or vehicle.display_name
            vehicle.model = item.get("car_type") or vehicle.model
            synced.append(vehicle)

        self.db.commit()
        for vehicle in synced:
            self.db.refresh(vehicle)
        return synced

    async def capture_snapshot(self, vehicle: Vehicle, wake: bool = True) -> VehicleSnapshot:
        if wake:
            try:
                await self.wake_vehicle(vehicle.vin)
            except TeslaAPIError:
                pass

        data = await self.get_vehicle_data(vehicle.vin)
        charge = data.get("charge_state") or {}
        vehicle_state = data.get("vehicle_state") or {}
        climate = data.get("climate_state") or {}

        snapshot = VehicleSnapshot(
            vehicle_id=vehicle.id,
            captured_at=datetime.utcnow(),
            odometer_miles=_safe_float(vehicle_state.get("odometer")),
            battery_percent=_safe_float(charge.get("battery_level")),
            est_range_miles=_safe_float(charge.get("est_battery_range")),
            charge_energy_added_kwh=_safe_float(charge.get("charge_energy_added")),
            charge_rate_mph=_safe_float(charge.get("charge_rate")),
            charging_state=charge.get("charging_state"),
            is_climate_on=climate.get("is_climate_on"),
            sentry_mode=vehicle_state.get("sentry_mode"),
            raw_json=json.dumps(data),
        )
        self.db.add(snapshot)
        self.db.commit()
        self.db.refresh(snapshot)
        return snapshot


def _safe_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
