"""Template narration and follow-ups for live POIs (no LLM)."""

from __future__ import annotations

import re


def interest_hook(tags: list[str], interests: list[str]) -> str:
    low = [t.lower() for t in tags]
    blob = " ".join(low)
    for i in interests:
        if i.lower() in blob or any(i.lower() in t for t in low):
            return f" Given your interest in {i.lower()}, this one is worth a closer look."
    return ""


def live_narration(
    name: str,
    category: str,
    short_description: str,
    interests: list[str],
    tags: list[str],
) -> str:
    desc = (short_description or "").strip()
    if desc:
        base = f"You're near {name}. {desc}"
    else:
        base = f"You're near {name} — a {category.lower()} worth a look from here."
    return base + interest_hook(tags, interests)


GENERIC_LINES = [
    "Hard to say more without a plaque in front of us — try asking about history, hours, or what to notice first.",
    "If you walk one or two blocks in any direction, the neighborhood rhythm usually changes fast.",
    "Worth a slow pass even if you do not go inside — sometimes the approach tells the story.",
]


def live_pick_reply(
    name: str,
    category: str,
    tags: list[str],
    message: str,
) -> str:
    msg = message.lower()
    blob = " ".join(tags).lower()

    if re.search(r"\b(hour|open|close|ticket|free|cost|price)\b", msg):
        return (
            "Hours and fees change — search the venue name for today's times before you detour."
        )
    if re.search(r"\b(who|built|architect|design|history|when|old)\b", msg):
        if "historic" in blob or "memorial" in blob or "castle" in blob:
            return (
                f"{name} reads as a historic place from the data we have — for dates and names, "
                "Wikipedia or the site’s own page will be more precise than guessing."
            )
        return (
            f"For dates, architects, or backstory on {name}, a quick search on the full name "
            "usually beats what we can infer from tags alone."
        )
    if re.search(r"\b(food|eat|coffee|restaurant|hungry)\b", msg):
        return (
            "Menus and kitchens change fast — if you are hunting food, side streets often beat "
            "the busiest corner for something memorable."
        )
    if re.search(r"\b(walk|path|trail|park|outside|view)\b", msg):
        return (
            "If you want air and views, orbit outward from the pin — parks and viewpoints "
            "often sit just off the main commercial frontage."
        )
    if re.search(r"\b(why|worth|interesting|best|favorite)\b", msg):
        return (
            f"{name} is on the list because it is notable nearby — whether it clicks for you "
            "depends on pace; even five minutes on site can anchor the day."
        )

    idx = sum(ord(c) for c in message) % len(GENERIC_LINES)
    return GENERIC_LINES[idx]
