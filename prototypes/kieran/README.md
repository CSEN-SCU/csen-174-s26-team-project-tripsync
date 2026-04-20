# Orbit — Kieran prototype

Interactive prototype for the **Orbit** product vision: map-based POIs, passive “heads-up” when you enter a radius, short spoken narration, and follow-up Q&A (template text — no LLM API keys).

## Stack

- **Backend:** FastAPI on port **8010** — `POST /api/nearby` (live OpenStreetMap via **Overpass**), `POST /api/narrate`, `POST /api/converse`. `GET /api/pois` is unused (markers come from `/api/nearby`).
- **Data (SQLite):** SQLAlchemy writes **`orbit_kieran.db`** in the backend folder — it **survives stopping** Uvicorn (same as any SQLite file). Users have **bcrypt-hashed passwords**; **`POST /api/users/sign-up`** creates an account, **`POST /api/users/sign-in`** only loads an existing one. REST also includes `GET|PUT /api/users/{id}/wishlist` and `GET|POST|DELETE /api/users/{id}/friends…`. The browser stores **user id + email** in `localStorage` after a successful auth so **Friends** and refresh keep working. Itineraries sync after a short debounce; if the account has no cloud data yet, your local wishlist is uploaded once.
- **Frontend:** Vite + React + Leaflet on port **5174** (proxies `/api` to the backend). The map is full-width; **Filters** (top-right) opens interests, passive mode, GPS / simulation, and compact place lists. **Now exploring**, **Next**, replay/stop/clear, and follow-up chat sit in a **bottom dock**.

## Live POIs and motion

- On load and whenever you move meaningfully, the app calls Overpass for **tourism**, **historic**, **museum / theatre / library / worship**, **named parks**, and some **natural** features inside a ~**2.4 km** radius (configurable in `App.jsx` as `NEARBY_RADIUS_KM`). For objects with **`wikipedia`** or **`wikidata`** tags, the backend fills **`short_description`** from **Wikipedia’s intro extract** (MediaWiki API) or a **Wikidata** English description when Wikipedia is missing; others keep a short template blurb (no OSM tag dump).
- **GPS watch** updates your position; the client estimates **bearing** and **speed** from recent fixes. Those are sent as `heading_deg` and `speed_mps` so the backend can **shift the search bbox forward** along your direction and **rank** results slightly ahead of you when you are moving.
- **Throttling:** refetch at most about every **14 s** unless you moved ~**100 m**, plus a forced refresh about every **55 s** so lists stay fresh if you drift slowly.
- If Overpass is unreachable, a tiny **static SCU fallback** list is used instead.

Be kind to public Overpass instances: [Overpass API usage](https://wiki.openstreetmap.org/wiki/Overpass_API).

## Run locally

**1. Backend**

```bash
cd prototypes/kieran/backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8010
```

**2. Frontend** (new terminal)

```bash
cd prototypes/kieran/frontend
npm install
npm run dev
```

Open **http://localhost:5174**. The UI calls the API at **http://127.0.0.1:8010/api** (this prototype’s port, to avoid clashes with other apps on 8001). You need **network** access for live POIs. Narration uses the **Web Speech API** (system voice). Optional: set **`VITE_API_URL`** in `frontend/.env` if the API lives elsewhere.

## Try it

- Allow **location**, or **click the map** to place yourself (e.g. San Francisco). Markers and the sidebar list should fill from OSM.
- Toggle **interests** to tweak narration hooks.
- **Passive mode:** crossing the ring triggers a one-time heads-up for that place.
- **Simulate a walk** drives sample SCU waypoints and updates heading/speed for the biased search.
- Chat uses keyword-based template replies grounded on the place name and OSM tags.
