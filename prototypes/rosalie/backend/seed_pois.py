"""
Curated Amsterdam POIs for gallery demos (no live Overpass dependency).
Coordinates are approximate public entrance / centroid points.
"""

from __future__ import annotations

import math
from typing import Any


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlng / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def walk_minutes(distance_km: float, kph: float = 4.75) -> float:
    """Rough walking time; ~4.75 km/h urban pace."""
    if distance_km <= 0:
        return 0.0
    return max(0.5, round((distance_km / kph) * 60, 1))


AMSTERDAM_POIS: list[dict[str, Any]] = [
    {
        "id": "anne_frank_huis",
        "name": "Anne Frank House",
        "lat": 52.3752,
        "lng": 4.8840,
        "category": "museum / historic house",
        "facts": "Canal house where Anne Frank hid during WWII; today a museum about her diary and the people in hiding.",
    },
    {
        "id": "rijksmuseum",
        "name": "Rijksmuseum",
        "lat": 52.3600,
        "lng": 4.8852,
        "category": "art museum",
        "facts": "National museum of the Netherlands; famous for Dutch Masters including Rembrandt's Night Watch.",
    },
    {
        "id": "van_gogh_museum",
        "name": "Van Gogh Museum",
        "lat": 52.3584,
        "lng": 4.8811,
        "category": "art museum",
        "facts": "Dedicated to Vincent van Gogh — the largest collection of his paintings and drawings in the world.",
    },
    {
        "id": "stedelijk",
        "name": "Stedelijk Museum",
        "lat": 52.3580,
        "lng": 4.8798,
        "category": "modern art museum",
        "facts": "Museum of modern and contemporary art and design, next to the Van Gogh and Rijksmuseum on Museumplein.",
    },
    {
        "id": "museum_van_loon",
        "name": "Museum Van Loon",
        "lat": 52.3602,
        "lng": 4.8914,
        "category": "museum house",
        "facts": "A canal-house museum on Keizersgracht showing how a wealthy Amsterdam family lived in the Golden Age.",
    },
    {
        "id": "royal_palace_dam",
        "name": "Royal Palace (Koninklijk Paleis), Dam Square",
        "lat": 52.37327,
        "lng": 4.89131,
        "category": "palace / civic building",
        "facts": "Amsterdam's main palace on Dam Square — built as the city hall in the Dutch Golden Age; today used for royal receptions and visitors can tour when open.",
    },
    {
        "id": "oude_kerk",
        "name": "Oude Kerk",
        "lat": 52.3742,
        "lng": 4.8980,
        "category": "historic church",
        "facts": "Amsterdam's oldest building; founded in the 13th century. Stands in the heart of the Red Light neighborhood.",
    },
    {
        "id": "begijnhof",
        "name": "Begijnhof",
        "lat": 52.3690,
        "lng": 4.8888,
        "category": "hidden courtyard",
        "facts": "A quiet enclosed courtyard with historic wooden houses — easy to miss from the busier streets nearby.",
    },
    {
        "id": "westertoren",
        "name": "Westerkerk",
        "lat": 52.3745,
        "lng": 4.8838,
        "category": "landmark church",
        "facts": "Rembrandt is buried in Westerkerk; the tower is a classic Amsterdam skyline cue near the canals.",
    },
    {
        "id": "nine_streets",
        "name": "De Negen Straatjes",
        "lat": 52.3696,
        "lng": 4.8865,
        "category": "shopping quarter",
        "facts": "Nine narrow streets of small shops and cafés between the main canals — good for a wandering afternoon.",
    },
    {
        "id": "herengracht_bridge",
        "name": "Herengracht canal bend",
        "lat": 52.3708,
        "lng": 4.8895,
        "category": "canal view",
        "facts": "Classic gabled houses along the Herengracht — the postcard Amsterdam canal curve.",
    },
    {
        "id": "centraal_station",
        "name": "Amsterdam Centraal",
        "lat": 52.3791,
        "lng": 4.9003,
        "category": "train station / landmark",
        "facts": "Neo-Renaissance station building on the IJ waterfront — the main rail gateway to the city.",
    },
    {
        "id": "bloemenmarkt",
        "name": "Bloemenmarkt (flower market)",
        "lat": 52.3668,
        "lng": 4.8915,
        "category": "market",
        "facts": "Floating stalls along the Singel — flowers, bulbs, and souvenirs in a glass-house setting.",
    },
    {
        "id": "rembrandthuis",
        "name": "Rembrandt House Museum",
        "lat": 52.3694,
        "lng": 4.9012,
        "category": "museum / historic house",
        "facts": "The house where Rembrandt lived and worked for years; restored rooms and etching studio.",
    },
    {
        "id": "scheepvaartmuseum",
        "name": "National Maritime Museum",
        "lat": 52.3717,
        "lng": 4.9152,
        "category": "museum",
        "facts": "Dutch maritime history in a former naval arsenal; ship models and the replica vessel Amsterdam outside.",
    },
    {
        "id": "nemo",
        "name": "NEMO Science Museum",
        "lat": 52.3742,
        "lng": 4.9123,
        "category": "science museum",
        "facts": "Copper-green science center shaped like a ship's hull — hands-on exhibits and a rooftop view.",
    },
    {
        "id": "vondelpark",
        "name": "Vondelpark (main entrance)",
        "lat": 52.3579,
        "lng": 4.8688,
        "category": "park",
        "facts": "Amsterdam's most famous park — open lawns, ponds, cafés, and busy with locals on sunny days.",
    },
    {
        "id": "albert_cuyp",
        "name": "Albert Cuyp Market",
        "lat": 52.3559,
        "lng": 4.8949,
        "category": "street market",
        "facts": "Long daily market in De Pijp — food, fabrics, and street snacks (try a stroopwafel warm).",
    },
    {
        "id": "foam",
        "name": "Foam Photography Museum",
        "lat": 52.3579,
        "lng": 4.8936,
        "category": "photography museum",
        "facts": "Canal-house museum focused on photography — rotating exhibitions in an intimate setting.",
    },
    {
        "id": "joods_historisch",
        "name": "Jewish Museum / Portuguese Synagogue area",
        "lat": 52.3674,
        "lng": 4.9048,
        "category": "museum / heritage",
        "facts": "Jewish Cultural Quarter with museums and the 17th-century Portuguese Synagogue complex nearby.",
    },
    {
        "id": "eye_filmmuseum",
        "name": "Eye Film Museum (north shore)",
        "lat": 52.3843,
        "lng": 4.9008,
        "category": "film museum / architecture",
        "facts": "Striking white building on the IJ north bank — cinema, exhibitions, and views back to the old city.",
    },
]


def pick_nearest(
    lat: float,
    lng: float,
    exclude_ids: set[str] | None = None,
    max_km: float = 2.5,
) -> tuple[dict[str, Any], float, float] | None:
    """Return (poi, distance_km, walk_minutes) for the nearest allowed POI within max_km."""
    exclude_ids = exclude_ids or set()
    best: tuple[dict[str, Any], float] | None = None
    for poi in AMSTERDAM_POIS:
        if poi["id"] in exclude_ids:
            continue
        d = haversine_km(lat, lng, poi["lat"], poi["lng"])
        if d > max_km:
            continue
        if best is None or d < best[1]:
            best = (poi, d)
    if best is None:
        return None
    poi, d_km = best
    return (poi, d_km, walk_minutes(d_km))
