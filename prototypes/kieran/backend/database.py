import os

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DB_PATH = os.path.join(os.path.dirname(__file__), "orbit_kieran.db")
engine = create_engine(f"sqlite:///{DB_PATH}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def ensure_sqlite_schema() -> None:
    """SQLite: add columns introduced after the first DB file was created."""
    insp = inspect(engine)
    if "users" not in insp.get_table_names():
        return
    cols = {c["name"] for c in insp.get_columns("users")}
    if "password_hash" not in cols:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255)"))


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
