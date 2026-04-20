[![Review Assignment Due Date](https://classroom.github.com/assets/deadline-readme-button-22041afd0340ce965d47ae6ef1cefeee28c7c493a6346c4f15d667ab976d596c.svg)](https://classroom.github.com/a/NfqHRKdw)

# TripSync (CSEN 174)

## Team

- Kieran Greeley
- GP Hora — Part 3 prototype: [`prototypes/gurprasaadhora/tripsync/`](./prototypes/gurprasaadhora/tripsync/)

## Repository layout

| Item | Purpose |
|------|---------|
| [`product-vision.md`](./product-vision.md) | Shared product vision for the team concept. |
| [`.cursorrules`](./.cursorrules) | Cursor / agent guidance (scope, secrets, prototypes). |
| [`prototypes/`](./prototypes/) | Each member’s divergent prototype in its own folder. |
| [`.gitignore`](./.gitignore) | Keeps `.env`, `node_modules`, build output, and local SQLite out of git. |

## Secrets

Do not commit API keys. Copy `prototypes/gurprasaadhora/tripsync/server/.env.example` to `server/.env` inside that app and add keys only on your machine.

## Run GP Hora’s prototype locally

```bash
cd prototypes/gurprasaadhora/tripsync
npm install
cp server/.env.example server/.env
# Add GROQ_API_KEY (and optionally PEXELS_API_KEY) in server/.env

npm run server   # terminal 1 — http://127.0.0.1:3001
npm run dev      # terminal 2 — http://127.0.0.1:5173
```

More detail: [`prototypes/gurprasaadhora/tripsync/README.md`](./prototypes/gurprasaadhora/tripsync/README.md).
- GP Hora

- Rosalie Wessels

- Daniel Louie
