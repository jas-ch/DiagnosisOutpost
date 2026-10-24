"""Simple migration runner for PostgreSQL/Cloud SQL.

For local SQLite, delete the local .db/.sqlite3 file and restart the app; the tables
will be recreated by Base.metadata.create_all(). SQLite's ALTER TABLE support is too
limited for this migration.
"""

import os
from pathlib import Path

from sqlalchemy import text

from app.database import engine


MIGRATIONS_DIR = Path(__file__).parent


def run_migrations():
    url = str(engine.url)
    if url.startswith("sqlite"):
        print("SQLite detected. Please delete the local database file and restart the app.")
        print(f"Database URL: {url}")
        return

    sql_files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not sql_files:
        print("No SQL migration files found.")
        return

    with engine.connect() as conn:
        for sql_file in sql_files:
            print(f"Running migration: {sql_file.name}")
            sql = sql_file.read_text()
            conn.execute(text(sql))
            conn.commit()
    print("Migrations completed.")


if __name__ == "__main__":
    run_migrations()
