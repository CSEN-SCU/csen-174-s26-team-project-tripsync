# Orbit Together — Iker's divergent prototype

**Question this prototype answers:** Is a **shared, multi-person session** a good
way to realize the Orbit product vision — where 2–5 friends join one room with a
4-character code, each contributes interests and a one-line vibe, and Orbit
surfaces nearby spots with a personal _"why YOU"_ line **per member**, then
narrates the walk over when the group converges on a pick?

All four other teammates built Orbit as a solo experience (map + audio for one
traveler). This prototype explores the **"Sync" in TripSync** literally — the
product as a group coordination tool for friends who can't agree on what to do
next.

## Storyboard

See [`storyboard.md`](./storyboard.md) for the full 6-frame arc. Persona:
**Priya, Marcus, and Leah** — a close friend trio on day one of a long weekend
in Lisbon, stuck on a park bench because nobody can agree on the next stop.

All 6 panels in [`assets/storyboard/`](./assets/storyboard) were generated as a
cohesive low-fidelity sketch series with a warm monochrome palette and a single
terracotta accent. A character reference was generated first (frame 1), then
used as a consistency reference for frames 2–6 — the same pattern the
assignment recommends for Nano Banana.

## Technical risk this answers

Per the assignment's _"focus on your biggest risks"_ guidance, this prototype
primarily answers an **architecture risk**: _can a shared-state flow of
information realize the product?_

- Can multiple clients stay synchronized well enough for a group-decision
  experience without full websockets?
- Can Groq generate _per-member_ "why you" reasons that actually feel tailored,
  or does the output collapse into generic blurbs?
- Is consensus surfacing (❤️ / 🤔 / 👎 + auto-nudge when the group leans) a
  better group-decision UX than a chat thread?

## Stack

| Layer | Choice |
|---|---|
| Frontend | Vite + React 19 + react-leaflet (port **5176**) |
| Backend | FastAPI + SQLAlchemy + httpx on port **8030** |
| Database | SQLite (`orbit_together.db`, written next to `main.py`, gitignored) |
| AI | Groq `llama-3.3-70b-versatile` for per-member POI reasons + group-aware narration |
| TTS | Browser Web Speech API (zero-latency, zero-keys — fine for a gallery-walk demo) |
| Map tiles | OpenStreetMap |

Ports are picked to avoid collisions with Kieran (5174/8010) and Rosalie
(5175/8020). All four backends can run side-by-side on the same laptop.

## Setup

### 1. Backend

```bash
cd prototypes/iker/backend
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS / Linux:
source .venv/bin/activate

pip install -r requirements.txt

cp .env.example .env     # Windows: copy .env.example .env
# Open .env and paste GROQ_API_KEY=... (free key at https://console.groq.com/keys)

uvicorn main:app --reload --port 8030
```

You should see `Uvicorn running on http://127.0.0.1:8030`. Hit
[http://127.0.0.1:8030/api/health](http://127.0.0.1:8030/api/health) to confirm
`groq_configured: true`.

If you don't set `GROQ_API_KEY`, the backend automatically falls back to
**seed mode** — curated hand-picked POIs for Lisbon, Barcelona, San Francisco,
and New York with deterministic per-member "why you" lines. The demo still
runs end-to-end. A badge in the top bar shows which mode you're in.

### 2. Frontend (new terminal)

```bash
cd prototypes/iker/frontend
npm install
npm run dev
```

Open [http://127.0.0.1:5176](http://127.0.0.1:5176).

## Demo script (for the Week 4 gallery walk)

**One-laptop version** (fastest to demo alone):

1. Land on the intro screen — read the "What it is / Who it's for / How to
   demo" copy.
2. Click **Start a session →**.
3. Pick **Lisbon**, then click **Be Priya** (fills in name + interests + vibe
   to match the storyboard character).
4. Click **Create + add the other two as demo personas** — this creates the
   session AND auto-joins Marcus and Leah with the exact interests from the
   storyboard.
5. You land in the session view with all three avatars on one Lisbon map.
6. Click **Get group picks →** in the bottom dock.
7. Each POI card shows a different _"why YOU"_ line for Priya, Marcus, and
   Leah — this is the core "aha" mechanic.
8. Tap ❤️ on the card you like. Use the **edit** button on the You panel to
   switch into Marcus, then Leah (their avatars still react as "you" since
   there's no auth — it's a demo). Or open a second browser window and join
   with the session code as a different person for a real multi-device demo.
9. Once a card has enough hearts, a **Let's go here** button appears. Tap it.
10. A green destination banner appears with Groq-generated narration
    addressing all three members by name. The browser reads it out loud.

**Two-laptop / phone version** (more compelling at the gallery walk):

1. On your laptop, start a session as Priya. Read out the 4-character code.
2. Hand the visitor your phone. They tap **Join with a code**, enter the
   code, type their own name and interests, and join.
3. The laptop screen live-updates with their avatar appearing on the map.
4. Tap **Get group picks** on either device. Both devices see the same 5
   cards with both visitor-and-Priya "why you" lines.
5. Each device reacts independently. The consensus badge surfaces as you
   both ❤️ the same card.
6. Tap **Let's go here**. Both devices play the same narration.

## Resetting between visitors

Use either:

- **Clear picks** button in the dock (keeps members, wipes POIs and reactions).
- **Leave** in the top bar, then create a fresh session for the next visitor.
- `DELETE /api/sessions/{code}` for a hard reset.

## API surface

All JSON, all on `http://127.0.0.1:8030`.

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/health` | `{groq_configured, cities, time}` |
| `POST` | `/api/sessions` | Create a session → 4-char code |
| `GET` | `/api/sessions/{code}/state` | Full session snapshot (polled every 2s) |
| `POST` | `/api/sessions/{code}/join` | Add a member |
| `PATCH` | `/api/members/{id}` | Update name/interests/vibe/location |
| `POST` | `/api/sessions/{code}/recommend` | Generate a fresh POI batch (Groq or seed) |
| `POST` | `/api/reactions` | Upsert one member's reaction to one POI |
| `POST` | `/api/sessions/{code}/pick` | Lock destination + generate group narration |
| `POST` | `/api/sessions/{code}/reset` | Soft reset (keep members, wipe picks) |
| `DELETE` | `/api/sessions/{code}` | Hard reset |

No auth. No passwords. Sessions live in SQLite until you delete them.

## What's intentionally not in scope

Following the assignment's _"focus on your biggest risks"_ guidance, these are
punted to the final project phase (weeks 5–9):

- **Real-time websockets.** 2s polling is enough to _feel_ live for a small
  group in the same room and avoids a whole class of bugs on a gallery-walk
  network.
- **Auth / persistent users.** Anyone with the 4-char code can join.
- **Live POIs via Overpass / Google Places.** The seed list is curated for
  the 4 demo cities; swapping in live POI data is a day of plumbing, not an
  architectural risk.
- **Server-side TTS.** Groq's Orpheus TTS would be a drop-in upgrade over
  the browser Web Speech API, but it needs another API round-trip and
  introduces network-dependent failure during demos. Rosalie's prototype
  already proves this works if we consolidate.
- **Deployment to a URL.** Runs locally on a laptop. That's the assignment's
  bar.

## Files

```
prototypes/iker/
├── README.md                     ← you are here
├── storyboard.md                 ← 6-frame arc + persona + quality check
├── assets/
│   └── storyboard/               ← 6 panel PNGs in consistent sketch style
├── backend/
│   ├── .env.example              ← GROQ_API_KEY, optional overrides
│   ├── requirements.txt
│   ├── main.py                   ← FastAPI routes + lifespan
│   ├── database.py               ← SQLAlchemy engine + SessionLocal + Base
│   ├── models.py                 ← Session / Member / POI / Reaction ORMs
│   ├── groq_service.py           ← Chat + JSON extraction + narration calls
│   └── seed_pois.py              ← Fallback POIs for Lisbon/BCN/SF/NYC
└── frontend/
    ├── package.json
    ├── vite.config.js            ← dev server 5176, /api proxy to 8030
    ├── index.html
    ├── .env.example
    └── src/
        ├── main.jsx
        ├── App.jsx               ← routing, polling, action fan-out
        ├── index.css             ← warm paper-and-terracotta palette
        ├── lib/api.js            ← thin fetch wrapper
        └── components/
            ├── IntroScreen.jsx
            ├── CreateJoinFlow.jsx
            ├── InterestPicker.jsx
            ├── SessionScreen.jsx
            ├── SessionMap.jsx
            ├── POIFeed.jsx
            └── DestinationBanner.jsx
```
