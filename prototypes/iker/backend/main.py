"""Orbit Together — FastAPI backend.

Shared real-time group trip sessions. See prototypes/iker/README.md for the full demo
script. Short version:

1. POST /api/sessions with a city → 4-char code.
2. Each friend POST /api/sessions/{code}/join with {name, avatar, interests}.
3. Every ~2s clients GET /api/sessions/{code}/state (poor-man's websocket).
4. Someone taps "Recommend" → POST /api/sessions/{code}/recommend.
   Backend calls Groq (if configured) for 5 group-aware POIs with per-member
   "why you" reasons, otherwise falls back to seed_pois for a stable demo.
5. Each member POST /api/reactions with love/maybe/nope per POI.
6. Group taps "Let's go" → POST /api/sessions/{code}/pick → Groq narration.

No websockets, no auth, no passwords. Demo only.
"""
from __future__ import annotations

import os
import random
import string
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Any

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, select
from sqlalchemy.orm import Session as SASession

from database import engine, get_db
from models import Member, POI, Reaction, Session as TripSession
from database import Base

from groq_service import (
    groq_configured,
    narrate_group_pick,
    recommend_pois,
)
from seed_pois import (
    CITY_CENTERS,
    build_seed_batch,
    city_center,
    fallback_narration,
)

load_dotenv()


# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: ARG001 (FastAPI contract)
    Base.metadata.create_all(bind=engine)
    yield


app = FastAPI(title="Orbit Together", version="0.1.0", lifespan=lifespan)

# Vite dev server default is 5173 + our picked 5176. Allow all localhost ports.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1):\d+",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

SESSION_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no O/0/I/1 ambiguity
ALLOWED_INTERESTS = {
    "food",
    "coffee",
    "views",
    "culture",
    "outdoors",
    "nightlife",
    "shopping",
    "quirky",
}


def _new_code(db: SASession) -> str:
    for _ in range(50):
        code = "".join(random.choices(SESSION_CODE_ALPHABET, k=4))
        if db.get(TripSession, code) is None:
            return code
    raise HTTPException(status_code=503, detail="Could not allocate session code")


def _member_dict(m: Member) -> dict[str, Any]:
    return {
        "id": m.id,
        "name": m.name,
        "avatar": m.avatar,
        "lat": m.lat,
        "lng": m.lng,
        "interests": m.interests,
        "vibe": m.vibe,
        "joined_at": m.joined_at.isoformat() if m.joined_at else None,
    }


def _poi_dict(p: POI, reactions_by_poi: dict[int, list[Reaction]]) -> dict[str, Any]:
    rx = reactions_by_poi.get(p.id, [])
    tally = {"love": 0, "maybe": 0, "nope": 0}
    per_member: dict[str, str] = {}
    for r in rx:
        if r.kind in tally:
            tally[r.kind] += 1
        per_member[str(r.member_id)] = r.kind
    return {
        "id": p.id,
        "batch_id": p.batch_id,
        "name": p.name,
        "category": p.category,
        "blurb": p.blurb,
        "lat": p.lat,
        "lng": p.lng,
        "walk_minutes": p.walk_minutes,
        "why": p.why,
        "reactions": tally,
        "member_reactions": per_member,
    }


def _session_state(db: SASession, code: str) -> dict[str, Any]:
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    members = list(
        db.scalars(select(Member).where(Member.session_code == code).order_by(Member.joined_at))
    )
    latest_batch = db.scalar(
        select(POI.batch_id)
        .where(POI.session_code == code)
        .order_by(POI.batch_id.desc())
        .limit(1)
    ) or 0
    pois = list(
        db.scalars(
            select(POI)
            .where(POI.session_code == code, POI.batch_id == latest_batch)
            .order_by(POI.id)
        )
    )
    poi_ids = [p.id for p in pois]
    reactions_by_poi: dict[int, list[Reaction]] = {}
    if poi_ids:
        for r in db.scalars(select(Reaction).where(Reaction.poi_id.in_(poi_ids))):
            reactions_by_poi.setdefault(r.poi_id, []).append(r)

    destination_poi = None
    if s.destination_poi_id is not None:
        dp = db.get(POI, s.destination_poi_id)
        if dp is not None:
            destination_poi = _poi_dict(dp, reactions_by_poi)

    return {
        "code": s.code,
        "city": s.city,
        "center": {"lat": s.center_lat, "lng": s.center_lng},
        "members": [_member_dict(m) for m in members],
        "pois": [_poi_dict(p, reactions_by_poi) for p in pois],
        "batch_id": latest_batch,
        "destination": destination_poi,
        "narration": s.narration,
        "last_recommended_at": s.last_recommended_at.isoformat() if s.last_recommended_at else None,
        "groq_configured": groq_configured(),
        "ai_source": "groq" if groq_configured() else "seed",
    }


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class CreateSessionIn(BaseModel):
    city: str = Field(default="Lisbon", max_length=80)
    center_lat: float | None = None
    center_lng: float | None = None


class JoinIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=40)
    avatar: str = Field(default="🙂", max_length=8)
    interests: list[str] = Field(default_factory=list)
    vibe: str = Field(default="", max_length=120)
    lat: float | None = None
    lng: float | None = None

    @field_validator("interests")
    @classmethod
    def _filter_interests(cls, v: list[str]) -> list[str]:
        return [s for s in {x.strip().lower() for x in v} if s in ALLOWED_INTERESTS][:8]


class UpdateMemberIn(BaseModel):
    name: str | None = Field(default=None, max_length=40)
    avatar: str | None = Field(default=None, max_length=8)
    interests: list[str] | None = None
    vibe: str | None = Field(default=None, max_length=120)
    lat: float | None = None
    lng: float | None = None

    @field_validator("interests")
    @classmethod
    def _filter_interests(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        return [s for s in {x.strip().lower() for x in v} if s in ALLOWED_INTERESTS][:8]


class ReactionIn(BaseModel):
    poi_id: int
    member_id: int
    kind: str

    @field_validator("kind")
    @classmethod
    def _k(cls, v: str) -> str:
        v = v.strip().lower()
        if v not in {"love", "maybe", "nope"}:
            raise ValueError("kind must be love|maybe|nope")
        return v


class PickIn(BaseModel):
    poi_id: int


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/api/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "groq_configured": groq_configured(),
        "cities": sorted(CITY_CENTERS.keys()),
        "time": datetime.utcnow().isoformat(),
    }


@app.post("/api/sessions")
def create_session(body: CreateSessionIn, db: SASession = Depends(get_db)) -> dict[str, Any]:
    city = body.city.strip() or "Lisbon"
    if city not in CITY_CENTERS:
        # Accept unknown cities but they'll use Lisbon coords unless client provides them.
        center = (body.center_lat, body.center_lng)
        if center[0] is None or center[1] is None:
            center = city_center(city)
    else:
        center = (
            body.center_lat if body.center_lat is not None else CITY_CENTERS[city][0],
            body.center_lng if body.center_lng is not None else CITY_CENTERS[city][1],
        )
    code = _new_code(db)
    s = TripSession(code=code, city=city, center_lat=center[0], center_lng=center[1])
    db.add(s)
    db.commit()
    return _session_state(db, code)


@app.get("/api/sessions/{code}/state")
def get_state(code: str, db: SASession = Depends(get_db)) -> dict[str, Any]:
    return _session_state(db, code.upper())


@app.post("/api/sessions/{code}/join")
def join_session(code: str, body: JoinIn, db: SASession = Depends(get_db)) -> dict[str, Any]:
    code = code.upper()
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    m = Member(
        session_code=code,
        name=body.name.strip()[:40],
        avatar=body.avatar or "🙂",
        lat=body.lat if body.lat is not None else s.center_lat,
        lng=body.lng if body.lng is not None else s.center_lng,
        vibe=body.vibe.strip(),
    )
    m.interests = body.interests
    db.add(m)
    db.commit()
    db.refresh(m)
    return {"member_id": m.id, "state": _session_state(db, code)}


@app.patch("/api/members/{member_id}")
def update_member(
    member_id: int, body: UpdateMemberIn, db: SASession = Depends(get_db)
) -> dict[str, Any]:
    m = db.get(Member, member_id)
    if m is None:
        raise HTTPException(status_code=404, detail="Member not found")
    if body.name is not None:
        m.name = body.name.strip()[:40] or m.name
    if body.avatar is not None:
        m.avatar = body.avatar or "🙂"
    if body.interests is not None:
        m.interests = body.interests
    if body.vibe is not None:
        m.vibe = body.vibe.strip()
    if body.lat is not None:
        m.lat = body.lat
    if body.lng is not None:
        m.lng = body.lng
    db.commit()
    return _session_state(db, m.session_code)


@app.post("/api/sessions/{code}/recommend")
async def recommend(code: str, db: SASession = Depends(get_db)) -> dict[str, Any]:
    code = code.upper()
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    members = list(
        db.scalars(select(Member).where(Member.session_code == code).order_by(Member.joined_at))
    )
    if not members:
        raise HTTPException(status_code=400, detail="Add at least one member first")

    member_payload = [
        {
            "id": m.id,
            "name": m.name,
            "interests": m.interests,
            "vibe": m.vibe,
        }
        for m in members
    ]

    used_source = "seed"
    batch: list[dict[str, Any]] = []
    if groq_configured():
        try:
            batch = await recommend_pois(
                city=s.city,
                center_lat=s.center_lat,
                center_lng=s.center_lng,
                members=member_payload,
            )
            used_source = "groq"
        except Exception as e:  # noqa: BLE001
            # Intentional: fall back to seed on any Groq failure so the demo never breaks.
            print(f"[orbit_together] Groq failed, falling back to seed: {e!r}")
            batch = []
    if not batch:
        batch = build_seed_batch(city=s.city, members=member_payload)
        used_source = "seed"

    # Bump batch id so the client sees a fresh list.
    prev_batch_id = (
        db.scalar(
            select(POI.batch_id)
            .where(POI.session_code == code)
            .order_by(POI.batch_id.desc())
            .limit(1)
        )
        or 0
    )
    next_batch_id = prev_batch_id + 1

    # Wipe old reactions + POIs so UI is clean.
    db.execute(
        delete(Reaction).where(
            Reaction.poi_id.in_(
                select(POI.id).where(POI.session_code == code)
            )
        )
    )
    db.execute(delete(POI).where(POI.session_code == code))

    for item in batch:
        p = POI(
            session_code=code,
            batch_id=next_batch_id,
            name=item["name"],
            category=item["category"],
            blurb=item["blurb"],
            lat=float(item["lat"]),
            lng=float(item["lng"]),
            walk_minutes=int(item["walk_minutes"]),
        )
        p.why = item.get("why") or {}
        db.add(p)

    s.destination_poi_id = None
    s.narration = ""
    s.last_recommended_at = datetime.utcnow()
    db.commit()

    state = _session_state(db, code)
    state["ai_source"] = used_source  # override with what actually happened this call
    return state


@app.post("/api/reactions")
def upsert_reaction(body: ReactionIn, db: SASession = Depends(get_db)) -> dict[str, Any]:
    poi = db.get(POI, body.poi_id)
    if poi is None:
        raise HTTPException(status_code=404, detail="POI not found")
    m = db.get(Member, body.member_id)
    if m is None or m.session_code != poi.session_code:
        raise HTTPException(status_code=400, detail="Member not in this session")

    existing = db.scalar(
        select(Reaction).where(
            Reaction.poi_id == body.poi_id, Reaction.member_id == body.member_id
        )
    )
    if existing is None:
        db.add(Reaction(poi_id=body.poi_id, member_id=body.member_id, kind=body.kind))
    else:
        existing.kind = body.kind
    db.commit()
    return _session_state(db, poi.session_code)


@app.post("/api/sessions/{code}/pick")
async def pick_destination(
    code: str, body: PickIn, db: SASession = Depends(get_db)
) -> dict[str, Any]:
    code = code.upper()
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    poi = db.get(POI, body.poi_id)
    if poi is None or poi.session_code != code:
        raise HTTPException(status_code=404, detail="POI not in this session")
    members = list(
        db.scalars(select(Member).where(Member.session_code == code).order_by(Member.joined_at))
    )
    member_payload = [
        {"id": m.id, "name": m.name, "interests": m.interests, "vibe": m.vibe}
        for m in members
    ]

    narration = ""
    if groq_configured():
        try:
            narration = await narrate_group_pick(
                city=s.city,
                poi_name=poi.name,
                poi_blurb=poi.blurb,
                members=member_payload,
                why_by_member=poi.why,
            )
        except Exception as e:  # noqa: BLE001
            print(f"[orbit_together] Groq narration failed: {e!r}")
            narration = ""
    if not narration:
        narration = fallback_narration(
            city=s.city,
            poi_name=poi.name,
            poi_blurb=poi.blurb,
            members=member_payload,
        )

    s.destination_poi_id = poi.id
    s.narration = narration
    db.commit()
    return _session_state(db, code)


@app.post("/api/sessions/{code}/reset")
def reset_session_contents(code: str, db: SASession = Depends(get_db)) -> dict[str, Any]:
    """Soft reset — keep the session + members, wipe POIs/reactions/destination."""
    code = code.upper()
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    db.execute(
        delete(Reaction).where(
            Reaction.poi_id.in_(select(POI.id).where(POI.session_code == code))
        )
    )
    db.execute(delete(POI).where(POI.session_code == code))
    s.destination_poi_id = None
    s.narration = ""
    s.last_recommended_at = None
    db.commit()
    return _session_state(db, code)


@app.delete("/api/sessions/{code}")
def nuke_session(code: str, db: SASession = Depends(get_db)) -> dict[str, Any]:
    """Full teardown — use between gallery-walk visitors for a clean slate."""
    code = code.upper()
    s = db.get(TripSession, code)
    if s is None:
        raise HTTPException(status_code=404, detail="Session not found")
    db.delete(s)
    db.commit()
    return {"ok": True, "deleted": code}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=os.getenv("HOST", "127.0.0.1"),
        port=int(os.getenv("PORT", "8030")),
        reload=True,
    )
