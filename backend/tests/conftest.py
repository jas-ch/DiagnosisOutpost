import os
from pathlib import Path

import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

# Force SQLite test database before importing the app module.
TEST_DB_PATH = Path(__file__).parent / "test.db"
os.environ["DATABASE_URL"] = f"sqlite:///{TEST_DB_PATH}"
os.environ["INGESTION_INTERVAL_MINUTES"] = "999999"
os.environ["INGEST_SECRET"] = "test-secret"

# Import after environment is set so app.database creates a SQLite engine.
from app.database import Base, get_db  # noqa: E402
from app.main import app  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

_engine = create_engine(
    os.environ["DATABASE_URL"],
    connect_args={"check_same_thread": False},
)
_TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_engine)


def _override_get_db():
    db = _TestSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override_get_db


@pytest.fixture(scope="function")
def client():
    # Start each test with a fresh schema.
    Base.metadata.drop_all(bind=_engine)
    Base.metadata.create_all(bind=_engine)

    with TestClient(app) as test_client:
        yield test_client

    # Clean up after the test.
    Base.metadata.drop_all(bind=_engine)
