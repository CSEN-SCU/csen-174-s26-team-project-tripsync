"""Offline seed POIs + deterministic per-member 'why you' lines.

Two uses:
1. Fallback when GROQ_API_KEY is not set or Groq fails (so the demo is always demo-able).
2. Grounding context — we can optionally hand Groq this list instead of asking it to
   invent coordinates from nothing.

Lat/lngs are real public places hand-picked for each city. Coordinates are approximate
and fine for demo radius math.
"""
from __future__ import annotations

import random
from typing import Any

# City centroids used when no geolocation is provided.
CITY_CENTERS: dict[str, tuple[float, float]] = {
    "Lisbon": (38.7139, -9.1394),
    "Barcelona": (41.3851, 2.1734),
    "San Francisco": (37.7749, -122.4194),
    "New York": (40.7580, -73.9855),
}


def city_center(city: str) -> tuple[float, float]:
    return CITY_CENTERS.get(city, CITY_CENTERS["Lisbon"])


# Each POI has a "tags" field of the same interest slugs used by the frontend:
#   food, coffee, views, culture, outdoors, nightlife, shopping, quirky
# When building per-member reasons, we match member interests against these tags.
_SEEDS: dict[str, list[dict[str, Any]]] = {
    "Lisbon": [
        {
            "name": "Manteigaria",
            "category": "food",
            "blurb": "Tiny pastel de nata bakery where you can watch them pull custard tarts out of the oven.",
            "lat": 38.7107,
            "lng": -9.1425,
            "walk_minutes": 6,
            "tags": ["food", "coffee", "quirky"],
        },
        {
            "name": "Miradouro de Santa Catarina",
            "category": "views",
            "blurb": "Hilltop terrace with a sweeping view over the Tagus river and 25 de Abril bridge.",
            "lat": 38.7099,
            "lng": -9.1464,
            "walk_minutes": 9,
            "tags": ["views", "outdoors", "nightlife"],
        },
        {
            "name": "Livraria Bertrand",
            "category": "culture",
            "blurb": "The oldest operating bookstore in the world, tucked into the Chiado district.",
            "lat": 38.7108,
            "lng": -9.1418,
            "walk_minutes": 5,
            "tags": ["culture", "shopping", "quirky"],
        },
        {
            "name": "Time Out Market Lisboa",
            "category": "food",
            "blurb": "Covered food hall with a curated mix of local chefs, pastries, and wine bars.",
            "lat": 38.7068,
            "lng": -9.1455,
            "walk_minutes": 11,
            "tags": ["food", "shopping"],
        },
        {
            "name": "Pensão Amor",
            "category": "nightlife",
            "blurb": "Bohemian ex-bordello reborn as a cocktail bar and bookshop, heavy velvet and red lamps.",
            "lat": 38.7071,
            "lng": -9.1446,
            "walk_minutes": 10,
            "tags": ["nightlife", "quirky", "culture"],
        },
        {
            "name": "Elevador de Santa Justa",
            "category": "views",
            "blurb": "Wrought-iron elevator connecting lower and upper Lisbon with a rooftop viewpoint.",
            "lat": 38.7119,
            "lng": -9.1394,
            "walk_minutes": 4,
            "tags": ["views", "culture", "quirky"],
        },
        {
            "name": "Jardim do Príncipe Real",
            "category": "outdoors",
            "blurb": "Leafy square under a huge cedar tree with benches, a tiny pond, and a Sunday market.",
            "lat": 38.7175,
            "lng": -9.1483,
            "walk_minutes": 13,
            "tags": ["outdoors", "coffee", "shopping"],
        },
        {
            "name": "Ginjinha Sem Rival",
            "category": "quirky",
            "blurb": "Hole-in-the-wall bar serving sour-cherry ginjinha into chocolate cups since 1890.",
            "lat": 38.7153,
            "lng": -9.1393,
            "walk_minutes": 3,
            "tags": ["nightlife", "quirky", "food"],
        },
    ],
    "Barcelona": [
        {
            "name": "Bar del Pla",
            "category": "food",
            "blurb": "Small Born tapas bar where locals crowd the counter for cod fritters and vermouth.",
            "lat": 41.3849,
            "lng": 2.1811,
            "walk_minutes": 7,
            "tags": ["food", "nightlife"],
        },
        {
            "name": "Bunkers del Carmel",
            "category": "views",
            "blurb": "Old anti-aircraft bunker turned free 360° viewpoint over all of Barcelona.",
            "lat": 41.4182,
            "lng": 2.1589,
            "walk_minutes": 14,
            "tags": ["views", "outdoors", "quirky"],
        },
        {
            "name": "El Born Cultural Centre",
            "category": "culture",
            "blurb": "Former market with an excavated 18th-century neighborhood visible through the floor.",
            "lat": 41.3851,
            "lng": 2.1824,
            "walk_minutes": 6,
            "tags": ["culture", "quirky"],
        },
        {
            "name": "Granja M. Viader",
            "category": "coffee",
            "blurb": "1870s milk bar famous for its thick hot chocolate and house-made cacaolat.",
            "lat": 41.3826,
            "lng": 2.1711,
            "walk_minutes": 8,
            "tags": ["coffee", "food", "quirky"],
        },
        {
            "name": "Parc de la Ciutadella",
            "category": "outdoors",
            "blurb": "Central park with a waterfall fountain, rowboat lake, and parrots in the palm trees.",
            "lat": 41.3886,
            "lng": 2.1866,
            "walk_minutes": 10,
            "tags": ["outdoors", "views"],
        },
        {
            "name": "Paradiso",
            "category": "nightlife",
            "blurb": "Speakeasy behind a pastrami sandwich shop — theatrical cocktails, book reservations.",
            "lat": 41.3842,
            "lng": 2.1829,
            "walk_minutes": 6,
            "tags": ["nightlife", "quirky"],
        },
        {
            "name": "La Central del Raval",
            "category": "shopping",
            "blurb": "Former 18th-century chapel converted into an art-and-design bookstore.",
            "lat": 41.3815,
            "lng": 2.1692,
            "walk_minutes": 9,
            "tags": ["shopping", "culture", "quirky"],
        },
    ],
    "San Francisco": [
        {
            "name": "Tartine Manufactory",
            "category": "food",
            "blurb": "Bakery-meets-restaurant famous for morning buns and naturally-leavened bread.",
            "lat": 37.7609,
            "lng": -122.4114,
            "walk_minutes": 12,
            "tags": ["food", "coffee"],
        },
        {
            "name": "Corona Heights Park",
            "category": "views",
            "blurb": "Short climb to bare red rocks with a 270° view of the whole city skyline.",
            "lat": 37.7654,
            "lng": -122.4386,
            "walk_minutes": 13,
            "tags": ["views", "outdoors"],
        },
        {
            "name": "City Lights Bookstore",
            "category": "culture",
            "blurb": "Independent bookstore + publisher that launched the Beat Generation in the 1950s.",
            "lat": 37.7976,
            "lng": -122.4066,
            "walk_minutes": 8,
            "tags": ["culture", "shopping", "quirky"],
        },
        {
            "name": "Sightglass Coffee",
            "category": "coffee",
            "blurb": "Cavernous roastery-cafe in an ex-industrial space, pour-overs and siphon bar.",
            "lat": 37.7781,
            "lng": -122.4100,
            "walk_minutes": 7,
            "tags": ["coffee", "quirky"],
        },
        {
            "name": "Dolores Park",
            "category": "outdoors",
            "blurb": "Sloping lawn that turns into an afternoon party with dogs, drums, and street food.",
            "lat": 37.7596,
            "lng": -122.4269,
            "walk_minutes": 11,
            "tags": ["outdoors", "views", "nightlife"],
        },
        {
            "name": "Trick Dog",
            "category": "nightlife",
            "blurb": "Mission cocktail bar whose menu changes every six months with a new themed book.",
            "lat": 37.7614,
            "lng": -122.4122,
            "walk_minutes": 10,
            "tags": ["nightlife", "quirky"],
        },
        {
            "name": "Wave Organ",
            "category": "quirky",
            "blurb": "Sound sculpture at the end of a jetty that plays the bay through pipes — best at high tide.",
            "lat": 37.8085,
            "lng": -122.4449,
            "walk_minutes": 15,
            "tags": ["quirky", "outdoors", "views"],
        },
    ],
    "New York": [
        {
            "name": "Russ & Daughters Cafe",
            "category": "food",
            "blurb": "Century-old appetizing shop's sit-down spinoff — lox, latkes, and egg creams.",
            "lat": 40.7218,
            "lng": -73.9881,
            "walk_minutes": 9,
            "tags": ["food", "culture"],
        },
        {
            "name": "The High Line",
            "category": "outdoors",
            "blurb": "Elevated park built on a disused freight rail line running along the West Side.",
            "lat": 40.7480,
            "lng": -74.0048,
            "walk_minutes": 14,
            "tags": ["outdoors", "views", "culture"],
        },
        {
            "name": "McNally Jackson",
            "category": "shopping",
            "blurb": "Independent bookstore with one of the best literary-events calendars in the city.",
            "lat": 40.7242,
            "lng": -73.9955,
            "walk_minutes": 8,
            "tags": ["shopping", "culture", "quirky"],
        },
        {
            "name": "Prince Street Pizza",
            "category": "food",
            "blurb": "Tiny slice shop whose spicy pepperoni squares have a line down the block most days.",
            "lat": 40.7232,
            "lng": -73.9942,
            "walk_minutes": 7,
            "tags": ["food", "quirky"],
        },
        {
            "name": "The Campbell",
            "category": "nightlife",
            "blurb": "Cocktail bar inside Grand Central — former 1920s private office with a vaulted ceiling.",
            "lat": 40.7527,
            "lng": -73.9772,
            "walk_minutes": 11,
            "tags": ["nightlife", "culture", "quirky"],
        },
        {
            "name": "Top of the Rock",
            "category": "views",
            "blurb": "Open-air observation deck with the clearest Empire State Building view in the city.",
            "lat": 40.7587,
            "lng": -73.9787,
            "walk_minutes": 12,
            "tags": ["views"],
        },
        {
            "name": "Bluestone Lane",
            "category": "coffee",
            "blurb": "Aussie-style flat-white cafe tucked beside a West Village church courtyard.",
            "lat": 40.7342,
            "lng": -74.0020,
            "walk_minutes": 10,
            "tags": ["coffee", "quirky"],
        },
    ],
}


# Interest-to-phrase banks used to build deterministic "why you" lines in fallback mode.
# Only hit when Groq isn't available. Keep them specific, avoid 'amazing / iconic'.
_REASON_BANK: dict[str, list[str]] = {
    "food": [
        "{name}, you'd eat well here — this is on the short list locals actually text each other about.",
        "{name}, this is the hands-in-the-air bite you came for. Counter seats beat the table.",
    ],
    "coffee": [
        "{name}, slow coffee vibe, a seat by the window, and nobody will rush you out.",
        "{name}, strong espresso and the kind of quiet corner you can actually hear yourself think in.",
    ],
    "views": [
        "{name}, this one's worth the climb — the reveal at the top is what people write home about.",
        "{name}, sunset hits right here and nobody rushes. Bring something to drink.",
    ],
    "culture": [
        "{name}, exactly the layer-under-the-city stop you like. One room carries more story than most museums.",
        "{name}, quiet, old, real. You'll stay longer than you planned.",
    ],
    "outdoors": [
        "{name}, shoes off, grass, a bench — a break the group actually needs.",
        "{name}, this is where you stop walking FOR something and walk IN it.",
    ],
    "nightlife": [
        "{name}, low-lit, good playlist, not a tourist bar. Perfect last-stop move.",
        "{name}, one round here and the whole night tilts in a better direction.",
    ],
    "shopping": [
        "{name}, a bring-something-home spot that isn't an airport gift shop.",
        "{name}, small-batch, no chains, things you'll actually keep.",
    ],
    "quirky": [
        "{name}, weird in the best way — you'll talk about this one on the flight home.",
        "{name}, pure story-fuel. Not on any top-ten list for a reason.",
    ],
}


_GENERIC_REASONS = [
    "{name}, solid group pick — enough going on that nobody's bored.",
    "{name}, easy yes. Good energy and low pressure to commit.",
    "{name}, a stop that works for the whole group, not a compromise.",
]


def _pick_reason(name: str, member_interests: list[str], tags: list[str], rng: random.Random) -> str:
    overlap = [t for t in (member_interests or []) if t in tags]
    bank: list[str]
    if overlap:
        key = rng.choice(overlap)
        bank = _REASON_BANK.get(key, _GENERIC_REASONS)
    else:
        bank = _GENERIC_REASONS
    return rng.choice(bank).format(name=name)


def build_seed_batch(
    *,
    city: str,
    members: list[dict[str, Any]],
    limit: int = 5,
    seed: int | None = None,
) -> list[dict[str, Any]]:
    """Return POI dicts in the same shape as groq_service.recommend_pois."""
    rng = random.Random(seed if seed is not None else random.randint(1, 10_000_000))
    pool = list(_SEEDS.get(city, _SEEDS["Lisbon"]))
    rng.shuffle(pool)
    chosen = pool[:limit]

    batch: list[dict[str, Any]] = []
    for p in chosen:
        why: dict[str, str] = {}
        for m in members:
            why[str(m["id"])] = _pick_reason(
                name=m.get("name") or "Friend",
                member_interests=m.get("interests") or [],
                tags=p.get("tags") or [],
                rng=rng,
            )
        batch.append(
            {
                "name": p["name"],
                "category": p["category"],
                "blurb": p["blurb"],
                "lat": p["lat"],
                "lng": p["lng"],
                "walk_minutes": p["walk_minutes"],
                "why": why,
            }
        )
    return batch


def fallback_narration(
    *,
    city: str,
    poi_name: str,
    poi_blurb: str,
    members: list[dict[str, Any]],
) -> str:
    names = [m["name"] for m in members] or ["friends"]
    if len(names) == 1:
        greet = names[0]
    elif len(names) == 2:
        greet = f"{names[0]} and {names[1]}"
    else:
        greet = f"{', '.join(names[:-1])}, and {names[-1]}"
    return (
        f"Alright {greet} — you're heading to {poi_name}. "
        f"{poi_blurb} I'll nudge you again when you're a block away."
    )
