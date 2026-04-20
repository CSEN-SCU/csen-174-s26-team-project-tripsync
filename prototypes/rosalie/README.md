# Orbit — Rosalie prototype

**Question this prototype answers:** Is a **listen-first, map-second** flow a good way to realize Orbit — where the app uses your location to **speak one short highlight** (with rough walk time) and only **opens a map** when you explicitly want wayfinding?

## What’s different

- **Audio-first:** Groq **LLM** writes the spoken line; Groq **TTS** (Orpheus) reads it. The main UI is not a map.
- **Map on demand:** After you hear the nudge, you can ask follow-ups; the **map appears only** when you tap **Show how to get there** (straight-line context between your simulated position and the place).
- **Curated Amsterdam spots** in `backend/seed_pois.py` so the demo works offline from external POI APIs (still needs network for Groq).

## Stack

- **Backend:** Starlette + Uvicorn (port **8020**), SQLite (`orbit_rosalie.db` next to `main.py`), `httpx` → Groq REST for chat + speech.
- **Frontend:** Vite + React + Leaflet (port **5175**, proxies `/api` → `8020`).

## API key (where to put it)

1. Copy `backend/.env.example` to **`prototypes/rosalie/backend/.env`** (same folder as `main.py`).
2. Set:

```bash
GROQ_API_KEY=your_key_here
```

Get a key at [Groq Console — API Keys](https://console.groq.com/keys).

Optional (defaults work for this demo):

- `GROQ_LLM_MODEL` — default `llama-3.3-70b-versatile`
- `GROQ_TTS_MODEL` — default `canopylabs/orpheus-v1-english`
- `GROQ_TTS_VOICE` — default `austin`

Do **not** commit `.env` (repo `.gitignore` already ignores it).

## Run locally

**Terminal 1 — API**

```bash
cd prototypes/rosalie/backend
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8020
```

**Terminal 2 — web UI**

```bash
cd prototypes/rosalie/frontend
npm install
npm run dev
```

Open **http://localhost:5175**. Allow a moment after “Hear a nearby highlight” for LLM + TTS.

## Try at the gallery walk

1. Read the **intro** card (who / problem / how to use).
2. Pick a **quick stand-in** location or edit lat/lng.
3. Tap **Hear a nearby highlight** → listen.
4. Optionally **Ask & listen** for a follow-up.
5. Tap **Show how to get there** only when you want the map.

If `GET /api/health` shows `"groq_configured": false`, the API will return **503** until `GROQ_API_KEY` is set in `backend/.env`.
