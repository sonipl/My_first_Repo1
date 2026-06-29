# Tesla Daily Usage Tracker
Track your Tesla's daily miles, charging, and battery usage from your phone.

This project includes:

- **Backend agent** (`backend/`) — FastAPI service that connects to the [Tesla Fleet API](https://developer.tesla.com/docs/fleet-api), captures vehicle snapshots, and aggregates daily usage automatically.
- **Mobile app** (`mobile/`) — Expo (React Native) app for iOS and Android with Today, History, and Settings screens.

## What it tracks daily

| Metric | Source |
|--------|--------|
| Miles driven | Odometer delta between snapshots |
| Energy charged | Charge energy added during the day |
| Battery % | Start/end state of charge |
| Charging sessions | Count of charge start events |
| Odometer | Latest reading |

## Architecture

```
Mobile App (Expo)  ──HTTP──▶  Backend API (FastAPI)
                                    │
                                    ├── Tesla Fleet API (OAuth)
                                    ├── SQLite database
                                    └── Daily scheduler (APScheduler)
```

The **daily agent** runs on a schedule (default: 23:55) and:

1. Refreshes Tesla tokens
2. Wakes each vehicle and captures a snapshot
3. Aggregates snapshots into a `daily_usage` record

You can also trigger a manual sync from the mobile app.

## Prerequisites

1. **Tesla Fleet API access** — Register at [developer.tesla.com](https://developer.tesla.com) and create an application.
2. **Node.js 18+** and **Python 3.11+**
3. **Expo Go** on your phone (for development) or EAS Build for production

## Backend setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env        # Edit with your Tesla client ID/secret
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Environment variables

| Variable | Description |
|----------|-------------|
| `TESLA_CLIENT_ID` | Fleet API client ID |
| `TESLA_CLIENT_SECRET` | Fleet API client secret |
| `TESLA_FLEET_API_URL` | Region endpoint (default: North America) |
| `TESLA_REDIRECT_URI` | OAuth callback URL |
| `APP_SECRET_KEY` | Random secret for device API tokens |
| `DAILY_SNAPSHOT_HOUR` | Hour for daily agent (0–23) |
| `DAILY_SNAPSHOT_MINUTE` | Minute for daily agent |

API docs: http://localhost:8000/docs

## Mobile app setup

```bash
cd mobile
npm install
```

Edit `app.json` → `extra.apiUrl` to point at your backend (use your machine's LAN IP for physical device testing, e.g. `http://192.168.1.10:8000`).

```bash
npx expo start
```

Scan the QR code with Expo Go (Android) or the Camera app (iOS).

## Connect your Tesla

### Option A: Refresh token (recommended for testing)

1. Complete Tesla Fleet API onboarding and generate a refresh token for your account.
2. Open the mobile app → **Settings**.
3. Paste the refresh token and tap **Connect**.

### Option B: OAuth

1. Set `TESLA_REDIRECT_URI` to your backend callback (`http://localhost:8000/auth/callback`).
2. In Settings, tap **Sign in with Tesla**.
3. Complete authorization in the browser, then refresh the Today screen.

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/devices/register` | Register mobile device |
| POST | `/auth/refresh-token` | Connect with Tesla refresh token |
| GET | `/auth/url` | Get OAuth authorization URL |
| GET | `/usage/today` | Today's usage summary |
| GET | `/usage/history` | Daily history (up to 365 days) |
| POST | `/agent/sync-now` | Manual snapshot + aggregation |
| POST | `/agent/run-daily` | Trigger scheduled agent manually |

All authenticated routes require headers:

```
X-Device-Id: <device_id>
Authorization: Bearer <api_token>
```

## Production notes

- Deploy the backend to a VPS or cloud provider with HTTPS.
- Use PostgreSQL instead of SQLite (`DATABASE_URL=postgresql://...`).
- Protect `/agent/run-daily` with an admin API key.
- For EU/other regions, update `TESLA_FLEET_API_URL` to your Tesla region endpoint.
- Consider [Fleet Telemetry](https://developer.tesla.com/docs/fleet-api/fleet-telemetry) for lower-cost streaming instead of polling `vehicle_data`.

## License

MIT
