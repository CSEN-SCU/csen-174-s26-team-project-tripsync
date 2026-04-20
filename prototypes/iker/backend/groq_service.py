"""Thin Groq client for Orbit Together.

Two jobs:
1. recommend_pois_prompt(): given a city + members' interests, ask Groq for a JSON list
   of 4-5 nearby POIs with per-member "why you" lines.
2. narrate_group_pick(): given a chosen POI + members, ask Groq for a 2-3 sentence
   group-aware audio-friendly intro as the trio walks over.

Network calls are isolated here so main.py stays a plain FastAPI router.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

import httpx

GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "llama-3.3-70b-versatile"


def _api_key() -> str:
    return (os.getenv("GROQ_API_KEY") or "").strip()


def groq_configured() -> bool:
    return bool(_api_key()) and os.getenv("ORBIT_USE_SEED_ONLY", "0").strip() != "1"


def _headers() -> dict[str, str]:
    key = _api_key()
    if not key:
        raise RuntimeError("GROQ_API_KEY is not set")
    return {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


async def _chat(system: str, user: str, max_tokens: int = 700, temperature: float = 0.7) -> str:
    model = (os.getenv("GROQ_LLM_MODEL") or DEFAULT_MODEL).strip()
    payload: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "temperature": temperature,
        "max_tokens": max_tokens,
    }
    async with httpx.AsyncClient(timeout=45.0) as client:
        r = await client.post(GROQ_CHAT_URL, headers=_headers(), json=payload)
        r.raise_for_status()
        data = r.json()
    try:
        return (data["choices"][0]["message"]["content"] or "").strip()
    except (KeyError, IndexError, TypeError) as e:
        raise RuntimeError("Unexpected Groq chat response shape") from e


def _extract_json_block(raw: str) -> Any:
    """Pull the first JSON object/array out of an LLM response.

    LLMs sometimes wrap JSON in ``` fences or prefix with prose. Be forgiving.
    """
    # Strip code fences.
    fenced = re.search(r"```(?:json)?\s*(.+?)```", raw, flags=re.DOTALL)
    candidate = fenced.group(1).strip() if fenced else raw.strip()
    # Find the outermost {...} or [...] in the candidate.
    m = re.search(r"(\[.*\]|\{.*\})", candidate, flags=re.DOTALL)
    if not m:
        raise ValueError("No JSON object/array found in model output")
    return json.loads(m.group(1))


async def recommend_pois(
    *,
    city: str,
    center_lat: float,
    center_lng: float,
    members: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Ask Groq for 5 group-aware POIs with per-member 'why you' reasons.

    Each member dict: {"id": int, "name": str, "interests": [str], "vibe": str}.
    Returns list of dicts shaped for POI rows:
        {name, category, blurb, lat, lng, walk_minutes, why: {member_id_str: reason}}
    """
    member_lines = []
    for m in members:
        tags = ", ".join(m.get("interests") or []) or "open to anything"
        vibe = (m.get("vibe") or "").strip()
        vibe_part = f' (mood: "{vibe}")' if vibe else ""
        member_lines.append(f'- id={m["id"]} name="{m["name"]}" likes: {tags}{vibe_part}')
    member_block = "\n".join(member_lines) or "- (nobody yet — return generic group picks)"

    system = (
        "You are Orbit, a friendly local travel guide helping a small group of friends "
        "pick their next stop in a city together. You know the neighborhood intimately "
        "and pick places real locals go. You never recommend tourist traps unless a "
        "member explicitly asks for the famous sights. Always answer as strict JSON."
    )
    user = (
        f"City: {city}\n"
        f"Group's current pin: lat {center_lat:.5f}, lng {center_lng:.5f}\n"
        f"Members currently in the session:\n{member_block}\n\n"
        "Return exactly 5 places within a ~15 minute walk of the pin. Mix categories "
        "(food, view, culture, quirky, outdoors) so the group has real options. For "
        "each place, write one short, specific 'why you' line PER MEMBER (8-18 words) "
        "that addresses that member by name and their actual interests/vibe. Keep the "
        "tone warm, concrete, and free of filler adjectives like 'amazing' or 'iconic'.\n\n"
        "Respond ONLY with JSON matching this schema:\n"
        "{\n"
        '  "places": [\n'
        "    {\n"
        '      "name": "string",\n'
        '      "category": "food|view|culture|outdoors|nightlife|quirky|coffee|shopping",\n'
        '      "blurb": "one neutral 1-sentence description (no member names)",\n'
        '      "lat": number,\n'
        '      "lng": number,\n'
        '      "walk_minutes": integer,\n'
        '      "why": { "<member_id>": "why THIS person would love it", ... }\n'
        "    }, ... 5 items total\n"
        "  ]\n"
        "}\n"
        "Use the exact member ids from above as keys in the 'why' object."
    )

    raw = await _chat(system, user, max_tokens=1200, temperature=0.8)
    data = _extract_json_block(raw)
    if isinstance(data, dict) and "places" in data:
        data = data["places"]
    if not isinstance(data, list):
        raise RuntimeError("Groq POI response was not a list")

    out: list[dict[str, Any]] = []
    for p in data:
        if not isinstance(p, dict):
            continue
        try:
            why_raw = p.get("why") or {}
            why = {str(k): str(v) for k, v in why_raw.items() if str(v).strip()}
            out.append(
                {
                    "name": str(p.get("name") or "").strip()[:120] or "Unnamed spot",
                    "category": str(p.get("category") or "place").strip()[:40],
                    "blurb": str(p.get("blurb") or "").strip()[:400],
                    "lat": float(p.get("lat") or center_lat),
                    "lng": float(p.get("lng") or center_lng),
                    "walk_minutes": max(1, int(p.get("walk_minutes") or 8)),
                    "why": why,
                }
            )
        except (ValueError, TypeError):
            continue
    return out[:5]


async def narrate_group_pick(
    *,
    city: str,
    poi_name: str,
    poi_blurb: str,
    members: list[dict[str, Any]],
    why_by_member: dict[str, str],
) -> str:
    """Generate a short group-aware intro (2-3 sentences) for the chosen POI."""
    member_lines = []
    for m in members:
        personal = why_by_member.get(str(m["id"])) or ""
        member_lines.append(
            f'- {m["name"]} (likes: {", ".join(m.get("interests") or []) or "anything"}): '
            f"personal hook = {personal!r}"
        )
    member_block = "\n".join(member_lines) or "- (solo)"

    system = (
        "You are Orbit, a friendly local travel guide. Speak TO a small group of "
        "friends who have just agreed on their next stop. Address them collectively "
        "by name (if given), be warm, and mention 1-2 concrete sensory details. Keep "
        "it to 2-3 sentences max — this is audio that plays while they walk over."
    )
    user = (
        f"City: {city}\n"
        f"Stop they just picked: {poi_name}\n"
        f"Neutral blurb: {poi_blurb}\n"
        f"Members:\n{member_block}\n\n"
        "Write the narration now. No markdown, no quotes, no list. Just the spoken text."
    )

    raw = await _chat(system, user, max_tokens=220, temperature=0.75)
    return raw.strip().strip('"').strip()
