"""
Orbit — Rosalie prototype: audio-first nudges with Groq LLM + TTS; map only when navigating.
"""

from __future__ import annotations

import json
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from sqlalchemy.orm import Session
from starlette.applications import Starlette
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Route

from database import Base, engine, SessionLocal
from groq_service import chat_completion, groq_configured, text_to_speech_wav, wav_to_data_url
from models import FollowUpTurn, ListeningEvent
from seed_pois import pick_nearest

load_dotenv()


@asynccontextmanager
async def lifespan(app: Starlette):
    Base.metadata.create_all(bind=engine)
    yield


def get_db() -> Session:
    return SessionLocal()


def _nudge_system() -> str:
    return (
        "You are Orbit, a warm, concise audio guide for walkers in Amsterdam. "
        "You speak short lines meant to be heard through earbuds — never read like an encyclopedia. "
        "Use ONLY the place facts provided. Do not invent dates, hours, prices, or names beyond what is given. "
        "Your job: one inviting sentence that mentions roughly how long it would take to walk there (use the walk minutes given). "
        "Optionally add a second short clause with a vivid but accurate hook from the facts. "
        "Do not say you are an AI. No bullet points. No markdown."
    )


def _nudge_user(poi: dict, walk_min: float, interests: list[str]) -> str:
    interest_line = ", ".join(interests) if interests else "general wandering"
    return (
        f"Place name: {poi['name']}\n"
        f"Category: {poi['category']}\n"
        f"Walk time from the listener (approximate): {walk_min} minutes.\n"
        f"Facts you may use (do not contradict): {poi['facts']}\n"
        f"Listener mood/interests (tone only): {interest_line}\n"
        "Write 1–2 sentences, conversational, for spoken audio."
    )


def _followup_system() -> str:
    return (
        "You are Orbit answering a follow-up question about a nearby place. "
        "Use ONLY the provided facts. If the answer is not in the facts, say you are not sure and suggest "
        "what they could look for on-site. "
        "2–4 short sentences, conversational, for spoken audio. No markdown."
    )


def _followup_user(poi: dict, question: str) -> str:
    return (
        f"Place: {poi['name']} ({poi['category']})\n"
        f"Facts: {poi['facts']}\n"
        f"Question: {question.strip()}"
    )


async def health(_: Request):
    return JSONResponse({"ok": True, "groq_configured": groq_configured()})


async def nudge(request: Request):
    if not groq_configured():
        return JSONResponse(
            {
                "detail": "Set GROQ_API_KEY in prototypes/rosalie/backend/.env (see .env.example).",
            },
            status_code=503,
        )

    try:
        body = await request.json()
    except json.JSONDecodeError:
        return JSONResponse({"detail": "Invalid JSON"}, status_code=400)

    lat = float(body.get("lat"))
    lng = float(body.get("lng"))
    exclude_ids = set(body.get("exclude_ids") or [])
    interests = body.get("interests") or ["history", "cafés", "quiet corners"]

    picked = pick_nearest(lat, lng, exclude_ids=exclude_ids)
    if picked is None:
        return JSONResponse(
            {
                "detail": "No curated spots within range — move the pin closer to central Amsterdam or clear exclusions.",
            },
            status_code=404,
        )

    poi, d_km, walk_min = picked
    db = get_db()
    try:
        try:
            script = await chat_completion(_nudge_system(), _nudge_user(poi, walk_min, interests))
        except Exception as e:
            return JSONResponse({"detail": f"Groq chat failed: {e!s}"}, status_code=502)

        if not script:
            return JSONResponse({"detail": "Empty script from Groq"}, status_code=502)

        try:
            wav = await text_to_speech_wav(script)
        except Exception as e:
            return JSONResponse({"detail": f"Groq TTS failed: {e!s}"}, status_code=502)

        ev = ListeningEvent(
            place_id=poi["id"],
            place_name=poi["name"],
            user_lat=lat,
            user_lng=lng,
            walk_minutes=walk_min,
            script_text=script,
            kind="nudge",
        )
        db.add(ev)
        db.commit()

        return JSONResponse(
            {
                "place": {
                    "id": poi["id"],
                    "name": poi["name"],
                    "lat": poi["lat"],
                    "lng": poi["lng"],
                    "category": poi["category"],
                    "facts": poi["facts"],
                },
                "distance_km": round(d_km, 3),
                "walk_minutes": walk_min,
                "script": script,
                "audio": wav_to_data_url(wav),
            }
        )
    finally:
        db.close()


async def followup(request: Request):
    if not groq_configured():
        return JSONResponse(
            {
                "detail": "Set GROQ_API_KEY in prototypes/rosalie/backend/.env (see .env.example).",
            },
            status_code=503,
        )

    try:
        body = await request.json()
    except json.JSONDecodeError:
        return JSONResponse({"detail": "Invalid JSON"}, status_code=400)

    place_id = body.get("place_id")
    place_name = body.get("place_name")
    category = body.get("category")
    facts = body.get("facts")
    question = (body.get("question") or "").strip()

    if not all([place_id, place_name, category, facts, question]):
        return JSONResponse(
            {"detail": "place_id, place_name, category, facts, and question are required"},
            status_code=400,
        )

    poi = {
        "id": place_id,
        "name": place_name,
        "category": category,
        "facts": facts,
    }
    db = get_db()
    try:
        try:
            answer = await chat_completion(
                _followup_system(),
                _followup_user(poi, question),
                max_tokens=320,
            )
        except Exception as e:
            return JSONResponse({"detail": f"Groq chat failed: {e!s}"}, status_code=502)

        if not answer:
            return JSONResponse({"detail": "Empty answer from Groq"}, status_code=502)

        try:
            wav = await text_to_speech_wav(answer)
        except Exception as e:
            return JSONResponse({"detail": f"Groq TTS failed: {e!s}"}, status_code=502)

        row = FollowUpTurn(place_id=str(place_id), question=question, answer=answer)
        db.add(row)
        db.commit()

        return JSONResponse({"answer": answer, "audio": wav_to_data_url(wav)})
    finally:
        db.close()


async def recent(request: Request):
    limit = min(int(request.query_params.get("limit") or 8), 30)
    db = get_db()
    try:
        rows = (
            db.query(ListeningEvent)
            .order_by(ListeningEvent.created_at.desc())
            .limit(limit)
            .all()
        )
        return JSONResponse(
            {
                "items": [
                    {
                        "id": r.id,
                        "at": r.created_at.isoformat(),
                        "place_name": r.place_name,
                        "walk_minutes": r.walk_minutes,
                        "kind": r.kind,
                    }
                    for r in rows
                ]
            }
        )
    finally:
        db.close()


routes = [
    Route("/api/health", endpoint=health, methods=["GET"]),
    Route("/api/nudge", endpoint=nudge, methods=["POST"]),
    Route("/api/followup", endpoint=followup, methods=["POST"]),
    Route("/api/recent", endpoint=recent, methods=["GET"]),
]

app = Starlette(routes=routes, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
