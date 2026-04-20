"""ORM models for Orbit Together.

Shape:
- Session:   a shared trip-planning room identified by a 4-char code.
- Member:    a person who joined a session (name, avatar emoji, location, interests).
- POI:       a point-of-interest suggestion in the session's current batch.
             Each POI carries a per-member "why you" reason map.
- Reaction:  a member's love / maybe / nope reaction on a POI. One row per (poi, member).
"""
from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database import Base


class Session(Base):
    __tablename__ = "sessions"

    code: Mapped[str] = mapped_column(String(4), primary_key=True)
    city: Mapped[str] = mapped_column(String(80), default="Lisbon")
    center_lat: Mapped[float] = mapped_column(Float, default=38.7139)
    center_lng: Mapped[float] = mapped_column(Float, default=-9.1394)
    destination_poi_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    narration: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    last_recommended_at: Mapped[datetime | None] = mapped_column(
        DateTime, nullable=True
    )

    members: Mapped[list["Member"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )
    pois: Mapped[list["POI"]] = relationship(
        back_populates="session", cascade="all, delete-orphan"
    )


class Member(Base):
    __tablename__ = "members"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_code: Mapped[str] = mapped_column(
        String(4), ForeignKey("sessions.code", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(60))
    avatar: Mapped[str] = mapped_column(String(8), default="🙂")
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    # JSON list of interest slugs (food, history, art, outdoors, nightlife, shopping, coffee, views)
    interests_json: Mapped[str] = mapped_column(Text, default="[]")
    # Small freeform note, e.g. "hungry", "tired feet", "wants a window seat"
    vibe: Mapped[str] = mapped_column(String(120), default="")
    joined_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    session: Mapped[Session] = relationship(back_populates="members")

    @property
    def interests(self) -> list[str]:
        try:
            v = json.loads(self.interests_json or "[]")
            return [str(x) for x in v] if isinstance(v, list) else []
        except Exception:
            return []

    @interests.setter
    def interests(self, value: list[str]) -> None:
        self.interests_json = json.dumps(list(value or []))


class POI(Base):
    __tablename__ = "pois"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    session_code: Mapped[str] = mapped_column(
        String(4), ForeignKey("sessions.code", ondelete="CASCADE"), index=True
    )
    batch_id: Mapped[int] = mapped_column(Integer, default=0, index=True)
    name: Mapped[str] = mapped_column(String(120))
    category: Mapped[str] = mapped_column(String(40), default="place")
    blurb: Mapped[str] = mapped_column(Text, default="")
    lat: Mapped[float] = mapped_column(Float)
    lng: Mapped[float] = mapped_column(Float)
    walk_minutes: Mapped[int] = mapped_column(Integer, default=8)
    # JSON dict member_id -> short reason string ("Leah: locals' pastel de nata spot")
    why_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    session: Mapped[Session] = relationship(back_populates="pois")

    @property
    def why(self) -> dict[str, str]:
        try:
            v = json.loads(self.why_json or "{}")
            return {str(k): str(w) for k, w in v.items()} if isinstance(v, dict) else {}
        except Exception:
            return {}

    @why.setter
    def why(self, value: dict[Any, str]) -> None:
        self.why_json = json.dumps({str(k): str(v) for k, v in (value or {}).items()})


class Reaction(Base):
    __tablename__ = "reactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    poi_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("pois.id", ondelete="CASCADE"), index=True
    )
    member_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("members.id", ondelete="CASCADE"), index=True
    )
    # "love" | "maybe" | "nope"
    kind: Mapped[str] = mapped_column(String(8), default="maybe")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
