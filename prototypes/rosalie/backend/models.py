from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import DateTime, Float, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


def utcnow():
    return datetime.now(timezone.utc)


class ListeningEvent(Base):
    """Persisted trail of what Orbit surfaced — proves DB use + gallery recap."""

    __tablename__ = "listening_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    place_id: Mapped[str] = mapped_column(String(64), index=True)
    place_name: Mapped[str] = mapped_column(String(256))
    user_lat: Mapped[float] = mapped_column(Float)
    user_lng: Mapped[float] = mapped_column(Float)
    walk_minutes: Mapped[float] = mapped_column(Float)
    script_text: Mapped[str] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(String(32), default="nudge")  # nudge | followup


class FollowUpTurn(Base):
    """Follow-up Q&A tied to the last place context."""

    __tablename__ = "followup_turns"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    place_id: Mapped[str] = mapped_column(String(64), index=True)
    question: Mapped[str] = mapped_column(Text)
    answer: Mapped[str] = mapped_column(Text)
