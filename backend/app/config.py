from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    tesla_client_id: str = ""
    tesla_client_secret: str = ""
    tesla_auth_url: str = "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3"
    tesla_fleet_api_url: str = "https://fleet-api.prd.na.vn.cloud.tesla.com"
    tesla_redirect_uri: str = "http://localhost:8000/auth/callback"

    app_secret_key: str = "dev-secret-change-me"
    database_url: str = "sqlite:///./tesla_tracker.db"

    daily_snapshot_hour: int = 23
    daily_snapshot_minute: int = 55


settings = Settings()
