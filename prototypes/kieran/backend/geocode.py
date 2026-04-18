"""Forward geocoding: Nominatim first, then Photon (Komoot) fallback — no API keys."""

from __future__ import annotations

import math
from typing import Any

import httpx

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
PHOTON_URL = "https://photon.komoot.io/api/"
USER_AGENT = "OrbitTripSyncPrototype/1.0 (university course project; contact via repo maintainer)"


def _viewbox(lat: float, lng: float, span_deg: float = 0.6) -> str:
    """west,south,east,north — preference bias, not strict bounds."""
    west = lng - span_deg
    east = lng + span_deg
    south = lat - span_deg * 0.75
    north = lat + span_deg * 0.75
    return f"{west},{south},{east},{north}"


def _nominatim_rows(
    query: str,
    bias_lat: float | None,
    bias_lng: float | None,
    limit: int,
) -> list[dict[str, Any]]:
    params: dict[str, str | int] = {
        "q": query,
        "format": "json",
        "limit": min(max(limit, 1), 12),
        "addressdetails": 0,
    }
    if bias_lat is not None and bias_lng is not None:
        if not (math.isnan(bias_lat) or math.isnan(bias_lng)):
            params["viewbox"] = _viewbox(float(bias_lat), float(bias_lng))
            params["bounded"] = 0

    headers = {"User-Agent": USER_AGENT, "Accept-Language": "en"}
    with httpx.Client(timeout=18.0) as client:
        r = client.get(NOMINATIM_URL, params=params, headers=headers)
        r.raise_for_status()
        rows = r.json()

    out: list[dict[str, Any]] = []
    for row in rows:
        try:
            la = float(row["lat"])
            lo = float(row["lon"])
        except (KeyError, TypeError, ValueError):
            continue
        label = (row.get("display_name") or row.get("name") or "").strip()
        if not label:
            continue
        out.append({"label": label, "lat": la, "lng": lo})
    return out


def _photon_label(props: dict[str, Any]) -> str:
    parts: list[str] = []
    name = (props.get("name") or "").strip()
    if name:
        parts.append(name)
    street = (props.get("street") or "").strip()
    if street and street != name:
        parts.append(street)
    locality = (
        props.get("city")
        or props.get("town")
        or props.get("village")
        or props.get("district")
        or ""
    )
    if isinstance(locality, str) and locality.strip():
        parts.append(locality.strip())
    state = (props.get("state") or "").strip()
    if state:
        parts.append(state)
    country = (props.get("country") or "").strip()
    if country:
        parts.append(country)
    return ", ".join(parts) if parts else name or "Place"


def _photon_rows(query: str, limit: int) -> list[dict[str, Any]]:
    with httpx.Client(timeout=15.0) as client:
        r = client.get(
            PHOTON_URL,
            params={"q": query, "limit": min(max(limit, 1), 15)},
            headers={"User-Agent": USER_AGENT},
        )
        r.raise_for_status()
        data = r.json()
    features = data.get("features") or []
    out: list[dict[str, Any]] = []
    for f in features[:limit]:
        geom = f.get("geometry") or {}
        coords = geom.get("coordinates") or []
        if len(coords) < 2:
            continue
        try:
            lo, la = float(coords[0]), float(coords[1])
        except (TypeError, ValueError):
            continue
        props = f.get("properties") or {}
        label = _photon_label(props if isinstance(props, dict) else {})
        if not label:
            continue
        out.append({"label": label, "lat": la, "lng": lo})
    return out


def search_places(
    query: str,
    bias_lat: float | None = None,
    bias_lng: float | None = None,
    limit: int = 10,
) -> list[dict[str, Any]]:
    q = (query or "").strip()
    if len(q) < 2:
        return []
    lim = min(max(limit, 1), 12)
    try:
        nom = _nominatim_rows(q, bias_lat, bias_lng, lim)
        if nom:
            return nom
    except (httpx.HTTPError, ValueError, TypeError, KeyError):
        pass
    try:
        return _photon_rows(q, lim)
    except (httpx.HTTPError, ValueError, TypeError, KeyError):
        return []
