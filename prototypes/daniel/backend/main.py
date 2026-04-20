import os
import math
import asyncio
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from sqlalchemy.orm import Session
from pydantic import BaseModel
import anthropic
import edge_tts

from database import get_db, engine, Base
from models import POI, ConversationLog, UserPreference
from seed import seed

load_dotenv()

_client = None


def get_claude_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise HTTPException(
                status_code=500,
                detail="ANTHROPIC_API_KEY not set. Add it to backend/.env",
            )
        _client = anthropic.Anthropic(api_key=api_key)
    return _client


SYSTEM_PROMPT = """You are Orbit, a knowledgeable AI travel companion riding along on a road trip. \
Speak naturally and casually, like a friendly guide who knows a lot about the area. \
Keep it concise —  1 SHORT sentence max for initial mentions. \
The initial mention is meant to be a quick and casual heads up \
For follow up questions, focus on specific, surprising facts or details, not general descriptions. \
Never use asterisks, action markers like *leans forward*, or roleplay formatting. \
Never start with "Oh" or exclamatory openers. Just talk normally. \
Things like "There's a cool mine that is open to vistors 10 miles away, want to check it out?" is the expected inital output, it SHOULD NOT BE MUCH LONGER THAN THIS \
If the traveler has relevant interests, connect the place to those interests naturally. \ 
these connections don't need to be formally addressed but rather suggest things that align with their interests \

"""


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    seed()
    yield


app = FastAPI(title="Orbit API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(dlng / 2) ** 2
    )
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# ── Request / Response schemas ──────────────────────────────────────

class NearbyRequest(BaseModel):
    lat: float
    lng: float
    radius_km: float = 30.0

class NarrateRequest(BaseModel):
    poi_id: int
    interests: list[str] = []

class ConverseRequest(BaseModel):
    poi_id: int
    message: str
    interests: list[str] = []

class InterestsUpdate(BaseModel):
    interests: list[str]


# ── Endpoints ───────────────────────────────────────────────────────

@app.get("/api/pois")
def list_all_pois(db: Session = Depends(get_db)):
    pois = db.query(POI).all()
    return [
        {
            "id": p.id,
            "name": p.name,
            "lat": p.lat,
            "lng": p.lng,
            "category": p.category,
            "short_description": p.short_description,
            "tags": p.tags,
        }
        for p in pois
    ]


@app.post("/api/nearby")
def find_nearby(req: NearbyRequest, db: Session = Depends(get_db)):
    pois = db.query(POI).all()
    nearby = []
    for p in pois:
        dist = haversine_km(req.lat, req.lng, p.lat, p.lng)
        if dist <= req.radius_km:
            nearby.append(
                {
                    "id": p.id,
                    "name": p.name,
                    "lat": p.lat,
                    "lng": p.lng,
                    "category": p.category,
                    "short_description": p.short_description,
                    "tags": p.tags,
                    "distance_km": round(dist, 2),
                }
            )
    nearby.sort(key=lambda x: x["distance_km"])
    return nearby


@app.post("/api/narrate")
def narrate_poi(req: NarrateRequest, db: Session = Depends(get_db)):
    poi = db.query(POI).filter(POI.id == req.poi_id).first()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    interests_str = ", ".join(req.interests) if req.interests else "general exploration"

    prompt = (
        f"The traveler is nearby: {poi.name}.\n"
        f"Category: {poi.category}\n"
        f"Traveler's interests: {interests_str}\n\n"
        f"Give ONLY a short 1-sentence heads-up, like: "
        f"\"You're near [place name], [one intriguing detail].\" "
        f"Do NOT describe the place in detail — just name it and hint at why "
        f"it's interesting. The traveler can ask to learn more if they want."
    )

    response = get_claude_client().messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=200,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": prompt}],
    )

    narration = response.content[0].text

    db.add(ConversationLog(poi_id=poi.id, role="assistant", content=narration))
    db.commit()

    return {"poi_id": poi.id, "name": poi.name, "narration": narration}


@app.post("/api/converse")
def converse_about_poi(req: ConverseRequest, db: Session = Depends(get_db)):
    poi = db.query(POI).filter(POI.id == req.poi_id).first()
    if not poi:
        raise HTTPException(status_code=404, detail="POI not found")

    history = (
        db.query(ConversationLog)
        .filter(ConversationLog.poi_id == req.poi_id)
        .order_by(ConversationLog.created_at.desc())
        .limit(10)
        .all()
    )
    history.reverse()

    context = (
        f"Context — the traveler is asking about: {poi.name}. "
        f"{poi.short_description} (Category: {poi.category}, Tags: {poi.tags}). "
        f"Traveler's interests: {', '.join(req.interests) if req.interests else 'general exploration'}."
    )

    messages = []
    for log in history:
        messages.append({"role": log.role, "content": log.content})
    messages.append({"role": "user", "content": req.message})

    # Claude requires messages to alternate user/assistant, starting with user
    if messages and messages[0]["role"] == "assistant":
        messages.insert(0, {"role": "user", "content": "Tell me about this place."})

    db.add(ConversationLog(poi_id=poi.id, role="user", content=req.message))

    response = get_claude_client().messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=300,
        system=f"{SYSTEM_PROMPT}\n\n{context}",
        messages=messages,
    )

    reply = response.content[0].text
    db.add(ConversationLog(poi_id=poi.id, role="assistant", content=reply))
    db.commit()

    return {"poi_id": poi.id, "name": poi.name, "reply": reply}


@app.get("/api/interests")
def get_interests(db: Session = Depends(get_db)):
    prefs = db.query(UserPreference).filter(UserPreference.active == 1).all()
    return [p.interest for p in prefs]


@app.put("/api/interests")
def update_interests(req: InterestsUpdate, db: Session = Depends(get_db)):
    db.query(UserPreference).delete()
    for interest in req.interests:
        db.add(UserPreference(interest=interest, active=1))
    db.commit()
    return req.interests


class TTSRequest(BaseModel):
    text: str
    voice: str = "en-US-AriaNeural"


@app.post("/api/tts")
async def text_to_speech(req: TTSRequest):
    try:
        communicate = edge_tts.Communicate(req.text, req.voice)
        audio_data = b""
        async for chunk in communicate.stream():
            if chunk["type"] == "audio":
                audio_data += chunk["data"]

        if not audio_data:
            raise HTTPException(status_code=500, detail="TTS produced no audio")

        return Response(
            content=audio_data,
            media_type="audio/mpeg",
            headers={"Cache-Control": "no-cache"},
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"TTS error: {str(e)}")


@app.delete("/api/conversation")
def clear_conversation(db: Session = Depends(get_db)):
    db.query(ConversationLog).delete()
    db.commit()
    return {"status": "cleared"}
