# TripSync / Orbit — Architecture Document

## What is Orbit?

Orbit is the team’s working name for the **audio-first TripSync experience**: an AI-powered audio travel guide for people exploring cities on foot. Rather than requiring the user to open an app and search, Orbit runs quietly in the background and pings the user through their earbuds when something interesting is nearby — for example, “Hey, there’s a 400-year-old spice market four minutes away, want to check it out?” The user can respond by voice, ask follow-up questions, get directions, or dismiss the suggestion. The full interaction is intended to be hands-free through whatever audio device they’re wearing.

The core experience is a **location-triggered voice conversation loop**:

1. The app detects the user’s position and queries the Cloud DB for nearby curated POIs.
2. The POI Ranker scores candidates against the user’s interests and filters out recently dismissed places.
3. If a strong match is found, the Voice Interface delivers an audio ping.
4. The user responds by voice; the Conversation Manager handles their reply via Claude.
5. The conversation continues until the user navigates, dismisses, or goes silent.
6. Inferred preferences are written back to the Cloud DB to improve future recommendations.

---

## Consolidation plan (TripSync team)

The repo is the **team’s home** for shared vision (`product-vision.md`) and **divergent prototypes** under `prototypes/<teammate>/`. This document is the **target consolidated architecture** for the hands-free, location-triggered guide—not a snapshot of every spike.

| Phase | Goal |
|--------|------|
| **Now** | Prove UX and technical risks in isolated prototypes (e.g. web vs mobile, different LLM providers, local vs hosted data). |
| **Consolidate** | One **Flutter** mobile app (iOS and Android) implementing the loop below: geo-aware POI fetch, ranking, voice I/O, Claude turns, and preference write-back via a **geo-capable Cloud DB**. |
| **Pre-launch hardening** | Add a thin **backend or BFF** so Claude (and other) API keys, quotas, and prompt templates are not shipped in the client—see [Key design decisions](#key-design-decisions). |

Alternate stacks in individual prototypes inform features and API shapes; they are **not** the long-term container set in the C4 diagrams below. During consolidation, those experiments should roll up into shared acceptance criteria and integration checks against this plan.

---

## Tech stack

### Mobile app — Flutter

The consolidated app is planned in **Flutter**, targeting iOS and Android from a single codebase. Flutter is appropriate here because the experience does not depend on AirPods-only APIs; audio playback, mic capture, geofencing, speech recognition, and TTS are available through mature Flutter packages.

### Audio — flutter_tts + speech_to_text

`flutter_tts` handles text-to-speech and routes through the active audio device (Bluetooth, wired, etc.). `speech_to_text` wraps platform speech recognition for on-device transcription. On iOS, `AVAudioSession` uses `.playAndRecord` with `.allowBluetooth` so audio routes to the headset where supported. Note: when the mic is active, Bluetooth often falls back to HFP/SCO (lower quality than A2DP)—a protocol limitation, not an app bug, and acceptable for voice assistant flows.

### Location — geolocator + geofencing

`geolocator` supports background location; **geofencing** (radius-based triggers) reduces polling and aligns better with background-location policy expectations. The app needs a clear **Always** location justification for store review.

### POI data — Cloud DB

POIs are **curated** in the Cloud DB (not live Google Places), for editorial control over recommendations. The store must support **geospatial queries** (POIs within a radius). Examples: Firebase with a geo package, or Supabase/Postgres with PostGIS.

### Conversation AI — Claude API

The Conversation Manager calls the **Claude API** per conversation turn. POI facts are injected into the system prompt so follow-ups stay grounded (“Is it open?”, “What do they serve?”). Turns are latency-sensitive; a fast Sonnet-class model is the default choice.

### User accounts + preferences — Cloud DB

Accounts, onboarding preferences, and inferred preferences live in the Cloud DB. The Conversation Manager writes inferred preferences after sessions so ranking improves over time.

### Navigation — URL deep-link

Directions open **Apple Maps** or **Google Maps** via deep link rather than in-app navigation, keeping scope tight.

---

## Key design decisions

**No dedicated backend server (initially).** Logic runs in the Flutter app; the device talks to the Cloud DB and Claude directly. This speeds early delivery but implies **API keys in the client** until a proxy exists—acceptable for development, not for a wide public launch.

**Curated POIs over live POI APIs.** Full control over quality and tone, at the cost of ongoing curation and a geo-indexed schema from day one.

**Ping fatigue prevention.** The POI Ranker should enforce cooldowns, hourly caps, and explicit “quiet” windows so proactive audio stays trustworthy.

---

## Architecture deliberation (trade-offs)

These diagrams reflect explicit trade-offs, not a first-pass box diagram:

- **Scale and secrets:** Client-direct Cloud DB + LLM simplifies the v1 topology but moves abuse risk and key management to the client; a **BFF** is the usual fix before scale.
- **Data freshness:** Curated POIs avoid noisy commercial listings but require a **curation pipeline**; there is no automatic “everything nearby” feed.
- **Latency:** Voice loops need fast turns; ranking and POI fetch must stay **small and local** (radius-limited queries, small candidate sets) so Claude is not blocked on large payloads.
- **Boundaries:** The **Voice Interface** is the only container that touches the OS audio stack; **Location Engine** owns geofence signals; **Conversation Manager** owns LLM prompts and session state—so testing and failure modes stay separable.

---

## C4 diagrams

The **context** diagram answers: *What does our system talk to?*  
The **container** diagram answers: *What are the major runnable/deployable pieces, and how does data flow?*

### Context diagram

**Narrative.** The **traveler** uses **Orbit** (single software system under design) for hands-free audio. Orbit reads and writes **Cloud DB** (POIs, accounts, preferences). It calls **Claude** for natural-language turns. For turn-by-turn directions it hands off to the **Maps app**. Audio playback and capture go through the **OS audio stack** (Bluetooth/wired routing, session category). No separate “backend” box appears in v1: the mobile app is the only TripSync-owned runtime between the user and external services.

```mermaid
C4Context
    title System context — TripSync / Orbit
    Person(traveler, "Traveler", "Explores on foot; hears pings and replies by voice")
    System(orbit, "Orbit", "AI audio travel guide (Flutter app — TripSync consolidated client)")
    SystemDb_Ext(db, "Cloud DB", "Curated geo POIs, accounts, preferences (e.g. PostGIS / Firebase geo)")
    System_Ext(claude, "Claude API", "Multi-turn conversation and tool-style prompts")
    System_Ext(maps, "Maps app", "Apple Maps / Google Maps — external navigation")
    System_Ext(audio, "OS audio stack", "TTS playback, mic capture, Bluetooth routing")
    Rel(traveler, orbit, "Uses hands-free")
    Rel(orbit, db, "Reads POIs; reads/writes user data and inferred preferences")
    Rel(orbit, claude, "Sends context + user turn; receives assistant reply")
    Rel(orbit, maps, "Opens directions via URL / deep link")
    Rel(orbit, audio, "Plays prompts; captures speech")
```

### Container diagram

**Narrative.** Everything in the **Orbit — Flutter mobile app** boundary runs on the device. The **Location Engine** subscribes to position and geofence events, loads **nearby POI candidates** from **Cloud DB**, and passes a small list to the **POI Ranker**. The ranker loads **user preferences** from the DB, applies cooldowns and interest scoring, and may hand a **top POI** to the **Conversation Manager**. The manager formats prompts, calls **Claude**, updates **inferred preferences** in the DB, and coordinates **navigation intent** to the maps app. The **Voice Interface** (TTS/STT) is the only container that speaks the **OS audio stack**; it exchanges text with the Conversation Manager. Data flow is **out-and-back**: location → DB → rank → optional ping → speech ↔ Claude ↔ speech, with preference writes closing the loop.

```mermaid
C4Container
    title Containers — Orbit (Flutter) and dependencies
    Person(traveler, "Traveler", "Explores on foot; hears pings and replies by voice")
    SystemDb_Ext(db, "Cloud DB", "Curated geo POIs, accounts, preferences")
    System_Ext(claude, "Claude API", "Conversation AI")
    System_Ext(maps, "Maps app", "External navigation")
    System_Boundary(app, "Orbit — Flutter mobile app") {
        Container(location, "Location Engine", "geolocator + geofencing", "Background position; proximity triggers; loads nearby POIs from DB")
        Container(ranker, "POI Ranker", "Dart", "Scores POIs vs interests; cooldowns and caps")
        Container(convo, "Conversation Manager", "Dart", "Prompts, session state, preference updates; calls Claude")
        Container(voice, "Voice Interface", "flutter_tts, speech_to_text", "Audio prompts; transcribes user speech")
    }
    Rel(traveler, voice, "Hears TTS; speaks replies")
    Rel(location, db, "Geo queries for nearby POIs")
    Rel(location, ranker, "Candidate POIs for current area")
    Rel(ranker, db, "Read preferences for scoring")
    Rel(ranker, convo, "Top POI / ping decision")
    Rel(convo, voice, "Text to speak")
    Rel(voice, convo, "Transcribed user text")
    Rel(convo, claude, "LLM request / response")
    Rel(convo, db, "Persist inferred preferences")
    Rel(convo, maps, "Launch directions when user asks")
```
