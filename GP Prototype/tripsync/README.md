# TripSync Prototype

TripSync is a local-first prototype of a location-aware travel companion:
- Frontend: React + Vite
- Backend: Node HTTP API (`server/index.js`)
- Database: persisted SQLite (`sql.js`, file-backed in `server/data/tripsync.sqlite`)
- AI integration: Gemini API (`generateContent`) for personalized place blurbs

## Run locally

In one terminal:

```bash
npm run server
```

In a second terminal:

```bash
npm run dev
```

Open the app at `http://127.0.0.1:5173`.

## Demo reset

On the intro screen, click **Reset Demo** before handing the laptop to the next visitor.

## Optional AI setup

Copy `.env.example` to `.env` and set:

```bash
GEMINI_API_KEY=your_key_here
```

If no API key is present, TripSync falls back to local generated recommendation copy so the prototype still works.
