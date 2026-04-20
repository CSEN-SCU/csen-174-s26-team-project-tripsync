# TripSync — GP Hora divergent prototype

**Repo path:** `prototypes/gurprasaadhora/tripsync` (Part 3 individual prototype).

TripSync is a gallery-walk demo: drop a map pin, get five curated nearby places with photos and “why you” copy, driven by onboarding interests and day preferences.

**Direction this prototype explores:** map-first, low-friction flow (pin + flip cards + numbered map stops) with **AI-first curation** (Groq) for consistent demo quality; optional live OSM via env flag.

## Stack
- Frontend: React + Vite (`http://127.0.0.1:5173`)
- Backend: Node + Express (`http://127.0.0.1:3001`)
- Database: SQLite (`better-sqlite3`)
- AI: Groq (default model from `server/.env`, e.g. `llama-3.1-8b-instant`)
- Places: default **AI geo curation**; set `TRIPSYNC_USE_LIVE_OVERPASS=1` in `server/.env` for Overpass + merge (see `server/.env.example`)
- Photos: Pexels API (optional; falls back to placeholder images)
- Map: Leaflet (CDN in `index.html`)

## Setup
1. From this directory:
   ```bash
   npm install
   ```
2. Create backend env file:
   ```bash
   cp server/.env.example server/.env
   ```
3. Add your keys in `server/.env` (required: `GROQ_API_KEY` for suggestions).

## Run
Terminal 1:
```bash
npm run server
```

Terminal 2:
```bash
npm run dev
```

Open `http://127.0.0.1:5173`.

## Demo reset
Use `GET /api/reset` or click reset from intro flow before next gallery visitor.
