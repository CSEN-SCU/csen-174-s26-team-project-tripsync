"""
Orbit prototype API — live POIs from OpenStreetMap (Overpass), optional static fallback,
template narration + rule-based follow-ups (no external LLM keys).
"""

from __future__ import annotations

import json
import os
import re
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import or_
from sqlalchemy.orm import Session

from auth_password import hash_password, verify_password
from database import Base, engine, ensure_sqlite_schema, get_db
from live_narrative import interest_hook as live_interest_hook
from live_narrative import live_narration, live_pick_reply
from geocode import search_places
from models import Friendship, User, WishlistSnapshot, utcnow
from overpass import fetch_pois_near, haversine_km

try:
    from dotenv import load_dotenv

    load_dotenv()
except Exception:
    # Optional dependency; API key can still be provided via environment variables.
    pass

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4.1-mini")
AI_CACHE_TTL_S = 60 * 30
_AI_CACHE: dict[tuple[str, str], tuple[float, str]] = {}


def _ai_cache_get(kind: str, key: str) -> str | None:
    row = _AI_CACHE.get((kind, key))
    if not row:
        return None
    ts, text = row
    if (time.time() - ts) > AI_CACHE_TTL_S:
        _AI_CACHE.pop((kind, key), None)
        return None
    return text


def _ai_cache_put(kind: str, key: str, text: str) -> None:
    _AI_CACHE[(kind, key)] = (time.time(), text)


def _get_openai_client():
    api_key = (os.getenv("OPENAI_API_KEY") or "").strip()
    if not api_key:
        return None
    try:
        from openai import OpenAI
    except Exception:
        return None
    return OpenAI(api_key=api_key)


def _poi_context(name: str, category: str, short_description: str, tags: list[str]) -> str:
    safe_tags = ", ".join(tags[:12]) if tags else "none"
    desc = short_description.strip() if short_description else "No extra description available."
    return (
        f"Place name: {name}\n"
        f"Category: {category}\n"
        f"Current description: {desc}\n"
        f"OSM tags/context: {safe_tags}\n"
    )


def _generate_ai_text(kind: str, cache_key: str, system: str, user: str) -> str | None:
    cached = _ai_cache_get(kind, cache_key)
    if cached:
        return cached
    client = _get_openai_client()
    if client is None:
        return None
    try:
        resp = client.responses.create(
            model=OPENAI_MODEL,
            temperature=0.5,
            max_output_tokens=220,
            input=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )
        text = (resp.output_text or "").strip()
    except Exception:
        return None
    if not text:
        return None
    _ai_cache_put(kind, cache_key, text)
    return text


def ai_narration(
    poi_id: str,
    name: str,
    category: str,
    short_description: str,
    interests: list[str],
    tags: list[str],
) -> str | None:
    interest_text = ", ".join(interests) if interests else "none specified"
    system = (
        "You are Orbit, a concise travel guide. Write exactly 1 or 2 sentences. "
        "Use only the provided context. Do not invent facts, dates, architects, or hours. "
        "Sound natural and helpful, and mention a detail that makes the place feel worth noticing."
    )
    user = (
        _poi_context(name, category, short_description, tags)
        + f"Traveler interests: {interest_text}\n"
        + "Write a short spoken heads-up for someone who is nearby."
    )
    return _generate_ai_text("narrate", f"{poi_id}|{interest_text}", system, user)


def ai_reply(
    poi_id: str,
    name: str,
    category: str,
    short_description: str,
    tags: list[str],
    interests: list[str],
    message: str,
) -> str | None:
    interest_text = ", ".join(interests) if interests else "none specified"
    system = (
        "You are Orbit, a concise local guide answering follow-up questions about one place. "
        "Answer in at most 3 sentences. Use only the provided context. "
        "If the answer is not in the context, say you are not sure and suggest checking the official site."
    )
    user = (
        _poi_context(name, category, short_description, tags)
        + f"Traveler interests: {interest_text}\n"
        + f"Question: {message}\n"
        + "Answer the question directly and naturally."
    )
    return _generate_ai_text("reply", f"{poi_id}|{message.strip().lower()}", system, user)

# ── Small offline fallback (SCU area) if Overpass is unreachable ─────

POIS: list[dict[str, Any]] = [
    {
        "id": 1,
        "name": "Mission Santa Clara de Asís",
        "lat": 37.34855,
        "lng": -121.93733,
        "category": "History",
        "tags": ["history", "architecture", "hidden gems"],
        "short_description": (
            "Mission Santa Clara de Asís — adobe, bells, and the rare feeling that "
            "1777 is only a courtyard away from your next class."
        ),
        "intro": (
            "You're near Mission Santa Clara — one of the original Spanish missions, "
            "still standing where students walk every day."
        ),
        "lines": [
            "The mission was founded in 1777 and rebuilt after earthquakes; the bell tower you see today is from the 19th century.",
            "Look for the rose garden beside the church — it's a quiet pocket that many visitors never notice.",
            "Mass and campus events still happen here, so it's a living landmark, not just a museum piece.",
        ],
    },
    {
        "id": 2,
        "name": "de Saisset Museum",
        "lat": 37.34912,
        "lng": -121.9389,
        "category": "Art & culture",
        "tags": ["art", "history", "hidden gems"],
        "short_description": (
            "de Saisset Museum — compact, free, and allergic to boredom: Mission-era "
            "artifacts shoulder-to-shoulder with contemporary Bay Area artists."
        ),
        "intro": (
            "You're by the de Saisset Museum — small, free, and full of California art "
            "and Mission-era artifacts most people rush past."
        ),
        "lines": [
            "The collection mixes contemporary Bay Area artists with objects tied to the Mission story.",
            "It's student-run in spirit: quick visits between classes work well — you don't need a whole afternoon.",
            "Ask at the desk for any rotating exhibits; they change more often than you'd expect for a campus museum.",
        ],
    },
    {
        "id": 3,
        "name": "Intel Museum",
        "lat": 37.3875,
        "lng": -121.9638,
        "category": "Tech",
        "tags": ["history", "tech"],
        "short_description": (
            "Intel Museum — sand-to-wafer-to-chip storytelling with buttons to press; "
            "Silicon Valley with the volume turned up."
        ),
        "intro": (
            "You're close to the Intel Museum — a surprisingly tactile explanation of how "
            "the silicon valley in 'Silicon Valley' actually gets built."
        ),
        "lines": [
            "Exhibits walk you from sand to wafer to chip — good context before any tech tour in the South Bay.",
            "It's family-friendly but detailed enough that adults who skipped physics still get the story.",
            "Check current hours online; they're stable but not 24/7 like a park.",
        ],
    },
]

STATIC_BY_SEED: dict[str, dict[str, Any]] = {f"seed-{p['id']}": p for p in POIS}


def static_fallback_rows(lat: float, lng: float, radius_km: float) -> list[dict[str, Any]]:
    out = []
    for p in POIS:
        d = haversine_km(lat, lng, p["lat"], p["lng"])
        if d <= radius_km:
            out.append(
                {
                    "id": f"seed-{p['id']}",
                    "name": p["name"],
                    "lat": p["lat"],
                    "lng": p["lng"],
                    "category": p["category"],
                    "short_description": p["short_description"],
                    "tags": p["tags"],
                    "distance_km": round(d, 3),
                    "osm_type": "seed",
                }
            )
    out.sort(key=lambda x: x["distance_km"])
    return out


def interest_hook(poi: dict[str, Any], interests: list[str]) -> str:
    tags = {t.lower() for t in poi.get("tags", [])}
    for i in interests:
        if i.lower() in tags:
            return f" Since you're into {i.lower()}, this spot lines up nicely with that."
    return ""


def pick_line_static(poi: dict[str, Any], message: str) -> str:
    msg = message.lower()
    lines: list[str] = poi["lines"]

    if re.search(r"\b(who|architect|design|built)\b", msg):
        return (
            lines[0]
            if poi["category"] == "History"
            else "The space was designed for casual visits — nothing overly formal, which keeps the barrier low."
        )
    if re.search(r"\b(when|year|old|history|started)\b", msg):
        return lines[0]
    if re.search(r"\b(eat|food|coffee|restaurant|menu)\b", msg):
        return (
            lines[1]
            if poi["category"] == "Food"
            else "If you're hungry, look a block or two off the main drag — that's usually where the quieter gems hide."
        )
    if re.search(r"\b(hour|open|close|ticket|free|cost)\b", msg):
        return "Hours and admission change seasonally — a quick web search for the official site beats me guessing wrong."
    if re.search(r"\b(why|worth|interesting|favorite|best)\b", msg):
        return lines[min(1, len(lines) - 1)]
    if re.search(r"\b(walk|path|loop|park|outside)\b", msg):
        return (
            lines[2]
            if poi["category"] == "Outdoors"
            else "If you want to stretch your legs, orbit a few blocks outward — density drops fast and it feels calmer."
        )

    idx = sum(ord(c) for c in message) % len(lines)
    return lines[idx]


@asynccontextmanager
async def lifespan(_app: FastAPI):
    Base.metadata.create_all(bind=engine)
    ensure_sqlite_schema()
    yield


app = FastAPI(title="Orbit Prototype (Kieran)", version="0.4.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class NearbyRequest(BaseModel):
    lat: float
    lng: float
    radius_km: float = 2.2
    heading_deg: float | None = None
    """Clockwise degrees from true north (0 = north), if known."""
    speed_mps: float | None = None
    """Ground speed in meters per second, if known."""


class NarrateRequest(BaseModel):
    poi_id: str
    interests: list[str] = Field(default_factory=list)
    name: str | None = None
    category: str | None = None
    short_description: str | None = None
    tags: list[str] = Field(default_factory=list)


class ConverseRequest(BaseModel):
    poi_id: str
    message: str
    interests: list[str] = Field(default_factory=list)
    name: str | None = None
    category: str | None = None
    short_description: str | None = None
    tags: list[str] = Field(default_factory=list)


class GeocodeRequest(BaseModel):
    q: str
    lat: float | None = None
    lng: float | None = None


def _normalize_email(email: str) -> str:
    return email.strip().lower()


MIN_PASSWORD_LEN = 8
MAX_PASSWORD_LEN = 72


class UserAuthRequest(BaseModel):
    email: str
    password: str = Field(min_length=MIN_PASSWORD_LEN, max_length=MAX_PASSWORD_LEN)


def _wishlist_payload_for_user(db: Session, user_id: int) -> dict[str, Any]:
    snap = db.query(WishlistSnapshot).filter(WishlistSnapshot.user_id == user_id).first()
    groups: list[Any] = []
    items: list[Any] = []
    if snap is not None:
        try:
            raw_g = json.loads(snap.groups_json or "[]")
            raw_i = json.loads(snap.items_json or "[]")
            groups = raw_g if isinstance(raw_g, list) else []
            items = raw_i if isinstance(raw_i, list) else []
        except json.JSONDecodeError:
            groups, items = [], []
    return {"groups": groups, "items": items}


@app.post("/api/users/sign-up")
def user_sign_up(req: UserAuthRequest, db: Session = Depends(get_db)):
    em = _normalize_email(req.email)
    if not em or "@" not in em:
        raise HTTPException(status_code=400, detail="A valid email is required.")
    if db.query(User).filter(User.email == em).first() is not None:
        raise HTTPException(
            status_code=409,
            detail="An account with this email already exists. Use Sign in instead.",
        )
    user = User(email=em, password_hash=hash_password(req.password))
    db.add(user)
    db.commit()
    db.refresh(user)
    wl = _wishlist_payload_for_user(db, user.id)
    return {"id": user.id, "email": user.email, "wishlist": wl}


@app.post("/api/users/sign-in")
def user_sign_in(req: UserAuthRequest, db: Session = Depends(get_db)):
    em = _normalize_email(req.email)
    if not em or "@" not in em:
        raise HTTPException(status_code=400, detail="A valid email is required.")
    user = db.query(User).filter(User.email == em).first()
    if user is None:
        raise HTTPException(
            status_code=404,
            detail="No account for this email. Use Sign up to create one.",
        )
    if user.password_hash is None:
        user.password_hash = hash_password(req.password)
        db.commit()
        db.refresh(user)
    elif not verify_password(req.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password.")

    wl = _wishlist_payload_for_user(db, user.id)
    return {"id": user.id, "email": user.email, "wishlist": wl}


class WishlistUpsertRequest(BaseModel):
    groups: list[Any] = Field(default_factory=list)
    items: list[Any] = Field(default_factory=list)


class AddFriendRequest(BaseModel):
    email: str


@app.get("/api/users/{user_id}/wishlist")
def get_wishlist(user_id: int, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(status_code=404, detail="User not found")
    snap = db.query(WishlistSnapshot).filter(WishlistSnapshot.user_id == user_id).first()
    if snap is None:
        return {"groups": [], "items": [], "updated_at": None}
    try:
        groups = json.loads(snap.groups_json or "[]")
        items = json.loads(snap.items_json or "[]")
    except json.JSONDecodeError:
        groups, items = [], []
    return {
        "groups": groups if isinstance(groups, list) else [],
        "items": items if isinstance(items, list) else [],
        "updated_at": snap.updated_at.isoformat() if snap.updated_at else None,
    }


@app.put("/api/users/{user_id}/wishlist")
def put_wishlist(user_id: int, req: WishlistUpsertRequest, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(status_code=404, detail="User not found")

    snap = db.query(WishlistSnapshot).filter(WishlistSnapshot.user_id == user_id).first()
    gj = json.dumps(req.groups)
    ij = json.dumps(req.items)
    now = utcnow()
    if snap is None:
        snap = WishlistSnapshot(user_id=user_id, groups_json=gj, items_json=ij, updated_at=now)
        db.add(snap)
    else:
        snap.groups_json = gj
        snap.items_json = ij
        snap.updated_at = now
    db.commit()
    db.refresh(snap)
    return {"ok": True, "updated_at": snap.updated_at.isoformat() if snap.updated_at else None}


@app.get("/api/users/{user_id}/friends")
def list_friends(user_id: int, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(status_code=404, detail="User not found")
    rows = (
        db.query(Friendship)
        .filter(or_(Friendship.user_low_id == user_id, Friendship.user_high_id == user_id))
        .all()
    )
    out: list[dict[str, Any]] = []
    for f in rows:
        oid = f.user_high_id if f.user_low_id == user_id else f.user_low_id
        other = db.query(User).filter(User.id == oid).first()
        if other is not None:
            out.append({"id": other.id, "email": other.email})
    return out


@app.post("/api/users/{user_id}/friends")
def add_friend(user_id: int, req: AddFriendRequest, db: Session = Depends(get_db)):
    u = db.query(User).filter(User.id == user_id).first()
    if u is None:
        raise HTTPException(status_code=404, detail="User not found")
    peer_em = _normalize_email(req.email)
    if not peer_em or "@" not in peer_em:
        raise HTTPException(status_code=400, detail="A valid friend email is required.")
    peer = db.query(User).filter(User.email == peer_em).first()
    if peer is None:
        raise HTTPException(
            status_code=404,
            detail="No account with that email. They need to sign up before you can connect.",
        )
    if peer.id == u.id:
        raise HTTPException(status_code=400, detail="You cannot add yourself as a friend.")

    lo, hi = (u.id, peer.id) if u.id < peer.id else (peer.id, u.id)
    existing = (
        db.query(Friendship)
        .filter(Friendship.user_low_id == lo, Friendship.user_high_id == hi)
        .first()
    )
    if existing is not None:
        return {"status": "already_friends", "friend": {"id": peer.id, "email": peer.email}}

    db.add(Friendship(user_low_id=lo, user_high_id=hi))
    db.commit()
    return {"status": "connected", "friend": {"id": peer.id, "email": peer.email}}


@app.delete("/api/users/{user_id}/friends/{friend_user_id}")
def remove_friend(user_id: int, friend_user_id: int, db: Session = Depends(get_db)):
    lo, hi = (
        (user_id, friend_user_id)
        if user_id < friend_user_id
        else (friend_user_id, user_id)
    )
    row = (
        db.query(Friendship)
        .filter(Friendship.user_low_id == lo, Friendship.user_high_id == hi)
        .first()
    )
    if row is None:
        raise HTTPException(status_code=404, detail="Friend link not found")
    db.delete(row)
    db.commit()
    return {"ok": True}


@app.get("/api/pois")
def list_pois():
    """Deprecated for the live app — markers come from /api/nearby. Kept for compatibility."""
    return []


@app.post("/api/geocode")
def geocode(req: GeocodeRequest):
    """Places search (Nominatim, then Photon fallback). Biases toward map anchor when lat/lng provided."""
    return search_places(req.q, req.lat, req.lng)


@app.post("/api/nearby")
def nearby(req: NearbyRequest):
    rows = fetch_pois_near(
        req.lat,
        req.lng,
        req.radius_km,
        req.heading_deg,
        req.speed_mps,
    )
    if not rows:
        rows = static_fallback_rows(req.lat, req.lng, req.radius_km)
    return rows


@app.post("/api/narrate")
def narrate(req: NarrateRequest):
    if req.poi_id.startswith("seed-"):
        poi = STATIC_BY_SEED.get(req.poi_id)
        if not poi:
            raise HTTPException(status_code=404, detail="POI not found")
        text = ai_narration(
            req.poi_id,
            poi["name"],
            poi["category"],
            poi["short_description"],
            req.interests,
            poi.get("tags", []),
        )
        if not text:
            text = poi["intro"] + interest_hook(poi, req.interests)
        return {"poi_id": req.poi_id, "name": poi["name"], "narration": text}

    if not req.name:
        raise HTTPException(
            status_code=400,
            detail="For live OSM places, include name (and ideally category, tags) from the nearby response.",
        )
    text = ai_narration(
        req.poi_id,
        req.name,
        req.category or "place",
        req.short_description or "",
        req.interests,
        req.tags,
    )
    if not text:
        text = live_narration(
            req.name,
            req.category or "place",
            req.short_description or "",
            req.interests,
            req.tags,
        )
    return {"poi_id": req.poi_id, "name": req.name, "narration": text}


@app.post("/api/converse")
def converse(req: ConverseRequest):
    if req.poi_id.startswith("seed-"):
        poi = STATIC_BY_SEED.get(req.poi_id)
        if not poi:
            raise HTTPException(status_code=404, detail="POI not found")
        reply = ai_reply(
            req.poi_id,
            poi["name"],
            poi["category"],
            poi["short_description"],
            poi.get("tags", []),
            req.interests,
            req.message,
        )
        if not reply:
            reply = pick_line_static(poi, req.message)
            if req.interests:
                hook = interest_hook(poi, req.interests).strip()
                if hook:
                    reply = reply.rstrip(".") + "." + hook
        return {"poi_id": req.poi_id, "name": poi["name"], "reply": reply}

    if not req.name:
        raise HTTPException(status_code=400, detail="Include name for live OSM follow-ups.")

    reply = ai_reply(
        req.poi_id,
        req.name,
        req.category or "place",
        req.short_description or "",
        req.tags,
        req.interests,
        req.message,
    )
    if not reply:
        reply = live_pick_reply(req.name, req.category or "place", req.tags, req.message)
        if req.interests:
            hook = live_interest_hook(req.tags, req.interests).strip()
            if hook:
                reply = reply.rstrip(".") + "." + hook
    return {"poi_id": req.poi_id, "name": req.name, "reply": reply}


@app.get("/api/health")
def health():
    return {"status": "ok", "live": "overpass", "static_fallback": len(POIS)}
