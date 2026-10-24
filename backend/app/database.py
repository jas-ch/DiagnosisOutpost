from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from app.config import get_database_url, get_settings

settings = get_settings()
database_url = get_database_url()

connect_args = {}
if database_url.startswith("sqlite"):
    connect_args = {"check_same_thread": False}
elif settings.cloud_sql_connection_name:
    # Cloud Run mounts the Cloud SQL proxy at this Unix socket.
    connect_args = {
        "unix_sock": f"/cloudsql/{settings.cloud_sql_connection_name}/.s.PGSQL.5432"
    }

engine = create_engine(database_url, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
