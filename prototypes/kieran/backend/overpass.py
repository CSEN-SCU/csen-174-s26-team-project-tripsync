"""
Live points of interest from OpenStreetMap via the public Overpass API.
Respect usage policy: https://wiki.openstreetmap.org/wiki/Overpass_API
"""

from __future__ import annotations

import math
import time
from typing import Any

import httpx

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
NEARBY_CACHE_TTL_S = 45.0
FAIL_CACHE_TTL_S = 12.0
_NEARBY_CACHE: dict[tuple, tuple[float, list[dict[str, Any]]]] = {}


def _cache_key(
    lat: float,
    lng: float,
    radius_km: float,
    heading_deg: float | None,
    speed_mps: float | None,
    max_results: int,
) -> tuple:
    # Quantize moving inputs so nearby, successive calls hit cache.
    return (
        round(lat, 3),
        round(lng, 3),
        round(radius_km, 2),
        None if heading_deg is None else int(heading_deg // 30),
        None if speed_mps is None else round(speed_mps, 1),
        max_results,
    )


def _clone_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [dict(r) for r in rows]


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(
        math.radians(lat2)
    ) * math.sin(dlng / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def offset_lat_lng(lat: float, lng: float, bearing_deg: float, distance_km: float) -> tuple[float, float]:
    """Destination point given start, bearing clockwise from north, distance in km."""
    if distance_km <= 0:
        return lat, lng
    r_earth = 6371.0
    brng = math.radians(bearing_deg)
    lat1 = math.radians(lat)
    lng1 = math.radians(lng)
    lat2 = math.asin(
        math.sin(lat1) * math.cos(distance_km / r_earth)
        + math.cos(lat1) * math.sin(distance_km / r_earth) * math.cos(brng)
    )
    lng2 = lng1 + math.atan2(
        math.sin(brng) * math.sin(distance_km / r_earth) * math.cos(lat1),
        math.cos(distance_km / r_earth) - math.sin(lat1) * math.sin(lat2),
    )
    return math.degrees(lat2), math.degrees(lng2)


def center_for_search(
    lat: float,
    lng: float,
    heading_deg: float | None,
    speed_mps: float | None,
) -> tuple[float, float]:
    """Search center (possibly nudged forward when moving)."""
    clat, clng = lat, lng
    if heading_deg is not None and speed_mps is not None and speed_mps > 0.5:
        ahead_km = min(2.2, speed_mps * 50.0 / 1000.0)
        clat, clng = offset_lat_lng(lat, lng, heading_deg, ahead_km)
    return clat, clng


def build_overpass_query(center_lat: float, center_lng: float, radius_km: float) -> str:
    r_m = max(300, int(radius_km * 1000))
    around = f"(around:{r_m},{center_lat},{center_lng})"
    return f"""[out:json][timeout:25];
(
  node["tourism"]{around};
  way["tourism"]{around};
  node["historic"]{around};
  way["historic"]{around};
  node["amenity"~"museum|gallery|theatre|library|arts_centre|place_of_worship"]{around};
  way["amenity"~"museum|gallery|theatre|library|arts_centre|place_of_worship"]{around};
  node["leisure"="park"]["name"]{around};
  way["leisure"="park"]["name"]{around};
  node["natural"~"peak|beach"]{around};
  way["natural"~"peak|beach"]{around};
);
out center tags;
"""


def _tags_to_kv(tags: dict[str, str]) -> list[str]:
    out: list[str] = []
    for k, v in tags.items():
        if k.startswith("name:") and k != "name:en":
            continue
        if k in ("source", "wikidata", "wikipedia", "website", "url"):
            continue
        if len(out) >= 12:
            break
        out.append(f"{k}={v}")
    return out


def _categorize(tags: dict[str, str]) -> str:
    t = tags.get("tourism", "")
    a = tags.get("amenity", "")
    le = tags.get("leisure", "")
    nat = tags.get("natural", "")
    if a == "museum" or t == "museum":
        return "Museum"
    if t in ("attraction", "viewpoint", "gallery", "theme_park", "zoo", "artwork"):
        return t.replace("_", " ").title()
    if a in ("theatre", "library", "arts_centre", "place_of_worship"):
        return a.replace("_", " ").title()
    if le == "park":
        return "Park"
    if nat in ("peak", "beach"):
        return nat.title()
    if tags.get("historic"):
        return "Historic"
    return "Point of interest"


def _orbit_blurb(name: str, tags: dict[str, str], category: str) -> str:
    """Short, human copy for UI — not dry tag dumps."""
    if tags.get("description"):
        d = tags["description"].strip().replace("\n", " ")
        if len(d) > 200:
            d = d[:197] + "…"
        return d

    t = tags.get("tourism", "")
    a = tags.get("amenity", "")
    le = tags.get("leisure", "")
    nat = tags.get("natural", "")
    hist = tags.get("historic", "")
    arch = tags.get("architect", "") or tags.get("artist_name", "")
    start = tags.get("start_date") or tags.get("year", "") or tags.get("built", "")
    denom = tags.get("denomination", "")
    religion = tags.get("religion", "")

    # Pick a template bucket from category + tags (deterministic variety)
    h = sum(ord(c) for c in name) % 4

    if a == "museum" or t == "museum":
        tails = [
            "Worth slowing down for — museums are where cities argue with themselves in objects.",
            "Curated quiet: the word museum usually means stories stacked floor to ceiling.",
            "If you only read plaques once today, make it here — density of context tends to be high.",
            "A pocket of intention: someone decided this collection mattered enough to keep doors open.",
        ]
        extra = f" ({start})" if start else ""
        return f"{name} — {tails[h]}{extra}"

    if t == "viewpoint" or nat in ("peak", "beach"):
        tails = [
            "A vantage point: light and distance change by the hour, so the same pin can feel new twice.",
            "The kind of place people detour for when they want the city to look like a postcard — then stay longer.",
            "Open air, big sky energy — good for resetting between dense blocks.",
            "If the wind picks up, that is part of the program; edges of cities feel more honest in weather.",
        ]
        return f"{name} — {tails[h]}"

    if le == "park" or t in ("theme_park", "zoo"):
        tails = [
            "Green punctuation in the street grid — parks are where locals rehearse being unhurried.",
            "Breathing room on the map: trees, paths, and the low odds anyone is rushing you.",
            "A soft landmark: you might remember the day by the bench you sat on, not the shop you passed.",
            "Good for stretching legs and attention spans — detail lives at walking speed.",
        ]
        return f"{name} — {tails[h]}"

    if a in ("theatre", "arts_centre") or t == "gallery":
        tails = [
            "Culture with a door handle — performances and walls that refuse to be wallpaper.",
            "Expect drama, color, or both — sometimes the lobby alone is worth the detour.",
            "A venue-shaped excuse to be curious; even the foyer often has opinions.",
            "If you like stories told out loud, this kind of pin is biased in your favor.",
        ]
        return f"{name} — {tails[h]}"

    if a == "place_of_worship" or hist:
        bits = []
        if hist:
            bits.append(f"Historic marker: {hist}.")
        if denom or religion:
            bits.append(f"{denom or religion} — layers of use and meaning stack here.")
        if arch:
            bits.append(f"Shaped by {arch.split(';')[0][:60]}{'…' if len(arch) > 60 else ''}.")
        tail = " ".join(bits) if bits else "Time-softened stone and ritual — the block feels different within a few meters."
        return f"{name} — {tail}"

    if t in ("attraction", "artwork"):
        tails = [
            "Listed as an attraction — could be iconic, quirky, or both; the street usually tells you which in ten paces.",
            "A deliberate pause in the sidewalk rhythm; worth a glance even if you do not go inside.",
            "Often photographed for a reason — the story is sometimes in the approach, not the ticket line.",
            "Low commitment, high serendipity: orbit it once and see what sticks.",
        ]
        return f"{name} — {tails[h]}"

    if a == "library":
        return (
            f"{name} — Public stacks and quiet ambition: libraries are cheat codes for "
            "learning a neighborhood without spending money."
        )

    tails = [
        f"{name} — A curiosity nearby: {category.lower()} on paper; in person it might surprise you either way.",
        f"{name} — Worth a slow pass — corners like this are how neighborhoods teach without a syllabus.",
        f"{name} — Could be a quick hello or a long rabbit hole; you will not know until you commit ten minutes.",
        f"{name} — Part of the city's footnotes; some footnotes age into legends.",
    ]
    return tails[h]


def _alignment_score(
    user_lat: float,
    user_lng: float,
    poi_lat: float,
    poi_lng: float,
    heading_deg: float | None,
    speed_mps: float | None,
) -> float:
    """
    Returns 0..1 where 1 means POI lies straight ahead along bearing.
    """
    if heading_deg is None or speed_mps is None or speed_mps < 0.4:
        return 0.0
    d_km = haversine_km(user_lat, user_lng, poi_lat, poi_lng)
    if d_km < 0.02:
        return 0.0
    # local tangent: north / east meters-ish
    dlat = (poi_lat - user_lat) * 111.0
    dlng = (poi_lng - user_lng) * 111.0 * max(0.25, math.cos(math.radians(user_lat)))
    norm = math.hypot(dlat, dlng)
    if norm < 1e-6:
        return 0.0
    vn, ve = dlat / norm, dlng / norm
    fn = math.cos(math.radians(heading_deg))
    fe = math.sin(math.radians(heading_deg))
    dot = max(-1.0, min(1.0, vn * fn + ve * fe))
    return max(0.0, dot)


def fetch_pois_near(
    lat: float,
    lng: float,
    radius_km: float,
    heading_deg: float | None,
    speed_mps: float | None,
    max_results: int = 55,
) -> list[dict[str, Any]]:
    now = time.time()
    key = _cache_key(lat, lng, radius_km, heading_deg, speed_mps, max_results)
    cached = _NEARBY_CACHE.get(key)
    if cached:
        ttl = FAIL_CACHE_TTL_S if not cached[1] else NEARBY_CACHE_TTL_S
        if (now - cached[0]) <= ttl:
            return _clone_rows(cached[1])

    center_lat, center_lng = center_for_search(lat, lng, heading_deg, speed_mps)
    q = build_overpass_query(center_lat, center_lng, radius_km)
    try:
        with httpx.Client(timeout=18.0) as client:
            r = client.post(OVERPASS_URL, data={"data": q})
            r.raise_for_status()
            data = r.json()
    except (httpx.HTTPError, ValueError, KeyError):
        _NEARBY_CACHE[key] = (now, [])
        return []

    elements = data.get("elements") or []
    seen: set[tuple[str, str, str]] = set()
    raw: list[dict[str, Any]] = []

    for el in elements:
        tags = el.get("tags") or {}
        name = tags.get("name") or tags.get("name:en") or tags.get("name:es")
        if not name or len(name) < 2:
            continue
        et = el.get("type")
        if et == "node":
            plat = el.get("lat")
            plng = el.get("lon")
        elif et == "way":
            c = el.get("center") or {}
            plat = c.get("lat")
            plng = c.get("lon")
        else:
            continue
        if plat is None or plng is None:
            continue

        dedupe = (f"{plat:.4f}", f"{plng:.4f}", name.lower())
        if dedupe in seen:
            continue
        seen.add(dedupe)

        category = _categorize(tags)
        tag_list = _tags_to_kv(tags)
        short_description = _orbit_blurb(name, tags, category)
        oid = el.get("id")
        if oid is None:
            continue
        poi_id = f"{et}/{oid}"

        d_km = haversine_km(lat, lng, plat, plng)
        align = _alignment_score(lat, lng, plat, plng, heading_deg, speed_mps)
        speed_factor = min(1.2, max(0.0, (speed_mps or 0) / 3.0))
        rank = d_km * (1.0 - 0.38 * speed_factor * align)

        raw.append(
            {
                "id": poi_id,
                "name": name,
                "lat": plat,
                "lng": plng,
                "category": category,
                "short_description": short_description,
                "tags": tag_list,
                "distance_km": round(d_km, 3),
                "_rank": rank,
                "osm_type": et,
            }
        )

    raw.sort(key=lambda x: x["_rank"])
    out = []
    for row in raw[:max_results]:
        row.pop("_rank", None)
        out.append(row)

    _NEARBY_CACHE[key] = (now, _clone_rows(out))
    if len(_NEARBY_CACHE) > 220:
        cutoff = now - max(NEARBY_CACHE_TTL_S, FAIL_CACHE_TTL_S)
        stale = [k for k, (ts, _) in _NEARBY_CACHE.items() if ts < cutoff]
        for sk in stale:
            _NEARBY_CACHE.pop(sk, None)
    return out
