"""
Orbit prototype API — live POIs from OpenStreetMap (Overpass), optional static fallback,
template narration + rule-based follow-ups (no external LLM keys).
"""

from __future__ import annotations

import re
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from live_narrative import interest_hook as live_interest_hook
from live_narrative import live_narration, live_pick_reply
from geocode import search_places
from overpass import fetch_pois_near, haversine_km

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


app = FastAPI(title="Orbit Prototype (Kieran)", version="0.2.0")

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
    tags: list[str] = Field(default_factory=list)


class GeocodeRequest(BaseModel):
    q: str
    lat: float | None = None
    lng: float | None = None


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
        text = poi["intro"] + interest_hook(poi, req.interests)
        return {"poi_id": req.poi_id, "name": poi["name"], "narration": text}

    if not req.name:
        raise HTTPException(
            status_code=400,
            detail="For live OSM places, include name (and ideally category, tags) from the nearby response.",
        )
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
        reply = pick_line_static(poi, req.message)
        if req.interests:
            hook = interest_hook(poi, req.interests).strip()
            if hook:
                reply = reply.rstrip(".") + "." + hook
        return {"poi_id": req.poi_id, "name": poi["name"], "reply": reply}

    if not req.name:
        raise HTTPException(status_code=400, detail="Include name for live OSM follow-ups.")

    reply = live_pick_reply(req.name, req.category or "place", req.tags, req.message)
    if req.interests:
        hook = live_interest_hook(req.tags, req.interests).strip()
        if hook:
            reply = reply.rstrip(".") + "." + hook
    return {"poi_id": req.poi_id, "name": req.name, "reply": reply}


@app.get("/api/health")
def health():
    return {"status": "ok", "live": "overpass", "static_fallback": len(POIS)}
