from functools import lru_cache
from urllib.parse import quote

from pydantic import ConfigDict
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Diagnosis Outpost Backend"
    debug: bool = False
    database_url: str = "sqlite:///./do_dev.db"
    # Cloud SQL PostgreSQL connection: set when running on Cloud Run.
    cloud_sql_connection_name: str = ""
    cloud_sql_user: str = ""
    cloud_sql_password: str = ""
    cloud_sql_database: str = ""
    cdc_data_url: str = ""
    who_data_url: str = ""
    ingestion_interval_minutes: int = 360  # 6 hours by default
    ingest_secret: str = ""  # Optional secret for POST /admin/ingest

    model_config = ConfigDict(env_file=".env")


@lru_cache
def get_settings() -> Settings:
    return Settings()


def get_database_url() -> str:
    """Return a SQLAlchemy database URL.

    Uses Cloud SQL PostgreSQL when CLOUD_SQL_CONNECTION_NAME is set; otherwise
    falls back to DATABASE_URL (SQLite for local dev).
    """
    s = get_settings()
    if s.cloud_sql_connection_name:
        # URL-encode credentials so special characters do not break the URL.
        # Host is left empty; database.py supplies the Unix socket path.
        user = quote(s.cloud_sql_user, safe="")
        password = quote(s.cloud_sql_password, safe="")
        return f"postgresql+pg8000://{user}:{password}@/{s.cloud_sql_database}"
    return s.database_url
