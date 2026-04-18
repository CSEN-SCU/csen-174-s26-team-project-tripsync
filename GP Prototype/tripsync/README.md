# TripSync Prototype

TripSync is a gallery-walk demo app that curates nearby places from a map pin.

## Stack
- Frontend: React + Vite (`http://127.0.0.1:5173`)
- Backend: Node + Express (`http://127.0.0.1:3001`)
- Database: SQLite (`better-sqlite3`)
- AI: Groq (`llama3-8b-8192`)
- Places: Overpass API
- Photos: Pexels API
- Map: Leaflet (CDN in `index.html`)

## Setup
1. Install dependencies:
   ```bash
   npm install
   ```
2. Create backend env file:
   ```bash
   cp server/.env.example server/.env
   ```
3. Add your keys in `server/.env`.

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
