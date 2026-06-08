# Orbit Final Technical Report

Orbit · Kieran Greeley, GP Hora, Rosalie Wessels, Daniel Louie, Iker Mendiburu · Spring 2026

> Export note: this Markdown file is the source for the graded PDF. Before submitting, export it to PDF with 11 pt body text and 1 inch margins. Items marked **NEEDS TEAM LINK/FILE** are intentionally visible placeholders for artifacts that were not present in the repository at drafting time.

## 1. Product vision and evolution

In W2, Orbit was framed as an AI-powered interactive travel guide for travelers who wanted meaningful points of interest without constant planning. The original vision emphasized location-aware recommendations, natural language generation, and conversational voice as an alternative to static map apps and pre-planned tours ([`product-vision.md`](product-vision.md)).

The current prototype still serves travelers exploring on foot, but the product narrowed from "smart map companion" to "screen-free audio guide." The app now prioritizes a foreground loop: sign in, choose interests, get a nearby place, hear an AI narration, and ask follow-up questions by voice. Three decisions bent the vision:

1. **Map-first discovery became audio-first guidance.** The early "map pin plus taste profile" idea was useful, but sprint feedback pushed the team toward earbuds and voice as the differentiator.
2. **Fully proactive pings were deferred.** Background geofencing and fatigue controls stayed in the target architecture, while Sprint 2 shipped a foreground voice session first.
3. **Natural onboarding became interest chips for v1.** Conversational onboarding remained a goal, but tap-to-select interests gave the team a shippable path through Firebase and Firestore.

The W2/W3 persona/storyboard artifact is not currently committed as a standalone file. **NEEDS TEAM FILE:** add or link the W2 persona/storyboard artifact, preferably under `docs/`, then cite it here. The product still serves that likely persona: a traveler who wants less planning and fewer choices, but now by listening and talking rather than scrolling.

**Section references:** [`product-vision.md`](product-vision.md), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md), **NEEDS TEAM FILE:** W2/W3 storyboard or persona artifact.

## 2. Architecture evolution

### W4 initial architecture

W4 described Orbit as a background, location-triggered voice loop. The planned app would detect location, query curated POIs, rank candidates, speak a proactive ping, handle speech follow-ups through an LLM, and open maps for directions. The diagram below is the W4 container diagram from [`architecture/architecture.md`](architecture/architecture.md).

```mermaid
C4Container
    title Containers — Orbit (Flutter) and dependencies
    Person(traveler, "Traveler", "Explores on foot; hears pings and replies by voice")
    SystemDb_Ext(db, "Cloud DB", "Curated geo POIs, accounts, preferences")
    System_Ext(LLM, "LLM API", "Conversation AI")
    System_Ext(maps, "Maps app", "External navigation")
    System_Boundary(app, "Orbit — Flutter mobile app") {
        Container(location, "Location Engine", "geolocator + geofencing", "Background position; proximity triggers; loads nearby POIs from DB")
        Container(ranker, "POI Ranker", "Dart", "Scores POIs vs interests; cooldowns and caps")
        Container(convo, "Conversation Manager", "Dart", "Prompts, session state, preference updates; calls LLM")
        Container(voice, "Voice Interface", "flutter_tts, speech_to_text", "Audio prompts; transcribes user speech")
    }
    Rel(traveler, voice, "Hears TTS; speaks replies")
    Rel(location, db, "Geo queries for nearby POIs")
    Rel(location, ranker, "Candidate POIs for current area")
    Rel(ranker, db, "Read preferences for scoring")
    Rel(ranker, convo, "Top POI / ping decision")
    Rel(convo, voice, "Text to speak")
    Rel(voice, convo, "Transcribed user text")
    Rel(convo, LLM, "LLM request / response")
    Rel(convo, db, "Persist inferred preferences")
    Rel(convo, maps, "Launch directions when user asks")
```

### W8 revised architecture

By W8/Sprint 2, the team had a foreground app rather than the full proactive loop. The revised architecture kept Firebase and LLM integration, but the live voice path moved into the Flutter app's home screen. Repo packages for the location engine, voice interface, and LLM integration existed, but several were not yet wired into the primary experience. The diagram below is the W8 current-state container diagram from [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md).

```mermaid
flowchart LR
    traveler(["Traveler<br/>signed-in or guest"])

    subgraph app["Orbit Flutter app — wired runtime"]
        direction TB
        main["App shell + AuthGate<br/>app/lib/main.dart"]
        auth["AuthService<br/>app/lib/auth/auth_service.dart"]
        prefs["FirestorePreferencesService<br/>app/lib/onboarding/"]
        poi_repo["PoiRepository<br/>app/lib/poi/poi_repository.dart"]
        home["Home screen + voice loop<br/>app/lib/home_screen.dart"]
        narrator["GroqPoiNarrator<br/>app/lib/groq_poi_narrator.dart"]
        tts["OpenRouterTts<br/>app/lib/openrouter_tts.dart"]
        loc["LocationService<br/>app/lib/location_service.dart"]
        llm_tab["LLM dev tab<br/>app/lib/llm_integration_screen.dart"]
    end

    subgraph stubs["Repo packages — NOT on voice path"]
        direction TB
        llm_pkg["llm_integration<br/>used by dev tab only"]
        voice_pkg["voice_interface stub<br/>throws UnimplementedError"]
        loc_pkg["location_engine<br/>algorithm only, no Firestore adapter"]
    end

    subgraph admin["Admin tooling — Node, off-device"]
        direction TB
        osm_gen["OSM POI generator<br/>geo-poi-database/"]
        seeder["POI seeder<br/>geo-poi-database/seed_pois.js"]
    end

    fb_auth[["Firebase Auth<br/>project orbit-86c27"]]
    firestore[("Cloud Firestore")]
    groq_chat[["Groq chat / Compound"]]
    openrouter_tts_ext[["OpenRouter TTS"]]
    osm_tiles[["OpenStreetMap tiles"]]
    overpass[["Overpass API"]]
    os[["Mobile OS<br/>STT, fallback TTS, GPS"]]

    traveler --> main
    traveler --> home

    main --> fb_auth
    auth --> fb_auth
    auth --> firestore
    prefs --> firestore

    home --> loc
    loc --> os
    home --> poi_repo
    poi_repo --> firestore
    home --> narrator
    narrator --> groq_chat
    home --> tts
    tts --> openrouter_tts_ext
    home --> os
    home --> osm_tiles
    llm_tab --> llm_pkg
    llm_pkg --> groq_chat

    osm_gen --> overpass
    osm_gen -.-> seeder
    seeder --> firestore

    classDef ext fill:#e8eef7,stroke:#3a5a8a,color:#111
    classDef stub fill:#fff7e6,stroke:#b88a4a,stroke-dasharray: 5 3,color:#111
    classDef wired fill:#e6f4ea,stroke:#1f7a36,color:#111
    classDef person fill:#fde7f3,stroke:#a3296b,color:#111

    class traveler person
    class fb_auth,firestore,groq_chat,openrouter_tts_ext,osm_tiles,overpass,os ext
    class llm_pkg,voice_pkg,loc_pkg stub
    class main,auth,prefs,poi_repo,home,narrator,tts,loc,llm_tab,seeder,osm_gen wired
```

### Current architecture at code freeze

The current code freeze is still close to the W8 shape: a consolidated Flutter app in `app/`, with supporting packages and admin tooling around it. The main difference is that saved interests now flow through `AuthGate` into `OrbitHomeScreen`, the settings/preferences screen lets users edit interests, wake-word handling is part of the live voice path, and OpenRouter is the cloud TTS provider. The seams are now clear: `AuthGate` routes users through sign-in and onboarding, `OrbitHomeScreen` coordinates location/POI/voice/chat, `PoiRepository` reads Firestore by geohash and tags, and `GroqPoiNarrator` produces grounded narration and follow-up answers.

```mermaid
flowchart LR
    traveler(["Traveler<br/>signed-in or guest"])

    subgraph app["Orbit Flutter app — current code freeze"]
        direction TB
        main["App shell + AuthGate<br/>app/lib/main.dart"]
        auth["AuthService<br/>app/lib/auth/auth_service.dart"]
        onboarding["Interest onboarding<br/>app/lib/onboarding/preferences_onboarding_screen.dart"]
        prefs["Preferences + settings<br/>app/lib/onboarding/ + app/lib/preferences/"]
        home["OrbitHomeScreen<br/>app/lib/home_screen.dart"]
        loc["LocationService<br/>app/lib/location_service.dart"]
        poi_repo["PoiRepository<br/>app/lib/poi/poi_repository.dart"]
        narrator["GroqPoiNarrator<br/>app/lib/groq_poi_narrator.dart"]
        wake["WakeWordSession<br/>voice-interface/"]
        headset["HeadsetMediaBridge<br/>app/lib/headset_media_bridge.dart"]
        cloud_tts["OpenRouterTts<br/>app/lib/openrouter_tts.dart"]
    end

    subgraph admin["Admin tooling — Node, off-device"]
        osm_gen["OSM POI generator<br/>geo-poi-database/generate_pois_from_osm.js"]
        seeder["POI seeder<br/>geo-poi-database/seed_pois.js"]
    end

    fb_auth[["Firebase Auth"]]
    firestore[("Cloud Firestore<br/>users + pois")]
    groq_chat[["Groq chat / Compound"]]
    openrouter[["OpenRouter TTS"]]
    os[["Mobile OS<br/>GPS, STT, fallback TTS, audio session"]]
    osm_tiles[["OpenStreetMap tiles"]]
    overpass[["Overpass API"]]

    traveler --> main
    main --> auth --> fb_auth
    main --> onboarding
    onboarding --> prefs
    prefs --> firestore
    main --> home
    home --> prefs
    home --> loc --> os
    home --> poi_repo --> firestore
    home --> narrator --> groq_chat
    home --> wake
    home --> headset --> os
    home --> cloud_tts --> openrouter
    home --> os
    home --> osm_tiles
    osm_gen --> overpass
    osm_gen -.-> seeder --> firestore

    classDef ext fill:#e8eef7,stroke:#3a5a8a,color:#111
    classDef wired fill:#e6f4ea,stroke:#1f7a36,color:#111
    classDef person fill:#fde7f3,stroke:#a3296b,color:#111

    class traveler person
    class fb_auth,firestore,groq_chat,openrouter,os,osm_tiles,overpass ext
    class main,auth,onboarding,prefs,home,loc,poi_repo,narrator,wake,headset,cloud_tts,seeder,osm_gen wired
```

Architectural decisions with repo evidence:

- **Background pings to foreground voice session.** The trigger was Sprint 2 velocity and iOS background-location risk. Evidence: W4 target in [`architecture/architecture.md`](architecture/architecture.md), shipped foreground flow in [`app/lib/home_screen.dart`](app/lib/home_screen.dart), and the tradeoff recorded in [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md).
- **Separate Conversation Manager to in-app `GroqPoiNarrator`.** The trigger was needing grounded follow-ups and a demoable voice path. Evidence: [`app/lib/groq_poi_narrator.dart`](app/lib/groq_poi_narrator.dart), package tests in [`tests/gp_llm_guardrails_test.dart`](tests/gp_llm_guardrails_test.dart), and the duplicate-stack debt in [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md).
- **Curated Firestore POIs over live places APIs.** The trigger was recommendation quality and lower API complexity. Evidence: [`geo-poi-database/seed_pois.js`](geo-poi-database/seed_pois.js), [`geo-poi-database/generate_pois_from_osm.js`](geo-poi-database/generate_pois_from_osm.js), [`app/lib/poi/poi_repository.dart`](app/lib/poi/poi_repository.dart), and [`firestore.rules`](firestore.rules).
- **Client-side secrets accepted for prototype, not production.** The trigger was course prototype speed. Evidence: [`app/.env.example`](app/.env.example) warns that keys in builds are extractable, while [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md) names a backend-for-frontend proxy as the production fix.

**Section references:** [`architecture/architecture.md`](architecture/architecture.md), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md), [`app/lib/main.dart`](app/lib/main.dart), [`app/lib/home_screen.dart`](app/lib/home_screen.dart), [`app/lib/poi/poi_repository.dart`](app/lib/poi/poi_repository.dart), [`app/lib/groq_poi_narrator.dart`](app/lib/groq_poi_narrator.dart).

## 3. Current state of the prototype

Today Orbit is an installable Flutter prototype distributed through TestFlight: <https://testflight.apple.com/join/4t68t4bB>. A user signs in with Google, selects interests, lands on a voice-first home screen, gets a location-based POI recommendation from Firestore, hears an AI-generated narration, and can ask follow-up questions by voice or keyboard.

Major feature entry points:

- App boot, Firebase initialization, auth routing: [`app/lib/main.dart`](app/lib/main.dart).
- Google sign-in and user profile creation: [`app/lib/auth/auth_service.dart`](app/lib/auth/auth_service.dart).
- Interest onboarding and saved preferences: [`app/lib/onboarding/preferences_onboarding_screen.dart`](app/lib/onboarding/preferences_onboarding_screen.dart), [`app/lib/onboarding/firestore_preferences_service.dart`](app/lib/onboarding/firestore_preferences_service.dart).
- Voice, wake-word, map preview, chat UI, and main session orchestration: [`app/lib/home_screen.dart`](app/lib/home_screen.dart).
- Nearby POI query and ranking: [`app/lib/poi/poi_repository.dart`](app/lib/poi/poi_repository.dart).
- LLM narration and follow-ups: [`app/lib/groq_poi_narrator.dart`](app/lib/groq_poi_narrator.dart).
- Cloud TTS: [`app/lib/openrouter_tts.dart`](app/lib/openrouter_tts.dart).
- POI admin seed pipeline: [`geo-poi-database/`](geo-poi-database/).

What it does not do yet: true background geofencing, proactive ping fatigue controls, maps deep links, inferred preference write-back after conversations, production-safe API key proxying, and broad automated app-level integration tests. The demo snapshot is tagged as [`final-demo`](https://github.com/CSEN-SCU/csen-174-s26-team-project-tripsync/tree/final-demo). **NEEDS TEAM LINK:** add the final demo video URL here and in the README.

**Section references:** live TestFlight URL in [`docs/sprint-1-cicd.md`](docs/sprint-1-cicd.md), current code-freeze commit `20a9049`, demo snapshot tag [`final-demo`](https://github.com/CSEN-SCU/csen-174-s26-team-project-tripsync/tree/final-demo), **NEEDS TEAM LINK:** demo video.

## 4. Engineering process: testing, security, deployment

### Testing

Planned strategy in W5: each teammate wrote failing tests at a public seam, then moved the smallest implementation green using a red-green-refactor loop. The plan deliberately covered separate risk areas: preferences, location/DB, LLM behavior, transcript normalization, and Firestore geohash querying ([`docs/sprint-1-testing.md`](docs/sprint-1-testing.md)).

Implemented strategy: the repo now has Dart package tests and Node tests. A representative methodical test is Iker's location/DB contract test in [`tests/iker_location_database_unit_test.dart`](tests/iker_location_database_unit_test.dart). It asserts user-visible behavior and system constraints: no DB query without location consent, bounded-radius POI lookup, graceful failure on DB errors, and current-position reads. AI helped draft tests and critique them, but human judgment corrected over-coupled assertions; the W5 testing doc records the before/after critique of a spy-counter-style assertion.

### Security

Planned strategy in W7/W9: protect private user data, avoid committing secrets, and minimize location risk. Implemented fixes include Firestore rules that restrict `/users/{userId}` documents to their owner while keeping POI reads public and admin-only for writes ([`firestore.rules`](firestore.rules)). The app also documents that API keys in client builds are extractable and should move behind a backend proxy before production ([`app/.env.example`](app/.env.example)). Human judgment decided that one-shot location was safer for the prototype than persistent background tracking; AI helped surface the backend-for-frontend proxy debt in the architecture retrospective.

### Deployment

Planned strategy in W6: GitHub Actions for automatic CI on pushes and PRs, plus TestFlight for distribution. Implemented pipeline stages include checkout, Dart dependency install, Dart tests, Node setup, Node dependency install, Node tests, and optional Firebase native config generation from secrets ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)). The Sprint 1 CI/CD write-up records the TestFlight URL and the initial CI setup commit `44c7b6685f294bf76a3bbff2da24e2d27451b66c` ([`docs/sprint-1-cicd.md`](docs/sprint-1-cicd.md)).

**Section references:** [`docs/sprint-1-testing.md`](docs/sprint-1-testing.md), [`tests/iker_location_database_unit_test.dart`](tests/iker_location_database_unit_test.dart), [`tests/gp_llm_guardrails_test.dart`](tests/gp_llm_guardrails_test.dart), [`firestore.rules`](firestore.rules), [`app/.env.example`](app/.env.example), [`.github/workflows/ci.yml`](.github/workflows/ci.yml), [`docs/sprint-1-cicd.md`](docs/sprint-1-cicd.md).

## 5. Successes, setbacks, and what would change

Successes:

1. **Everyone shipped a visible slice.** Sprint 1 produced a buildable app shell, TestFlight distribution, CI/CD, seeded Firebase POIs, and working development environments. That worked because the team split by subsystem early, then consolidated later ([`docs/sprint-1-retro.md`](docs/sprint-1-retro.md)).
2. **The team converged from prototypes to one Flutter app.** Sprint 2 connected auth, onboarding, location, POIs, voice, and LLM narration into a phone-runnable loop. The practice to keep is writing architecture retrospectives when the implementation diverges from the plan ([`docs/sprint-2-retro.md`](docs/sprint-2-retro.md), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md)).
3. **AI accelerated unfamiliar integration work.** Claude/Cursor helped with Flutter setup, CI, Groq prompts, Firestore queries, merge conflicts, and voice bugs. The useful pattern was asking with the repo open, then checking the output against actual files and tests.

Setbacks:

![Sprint 1 Orbit Kanban board evidence](docs/sprint-board-sprint-1.svg)

1. **Cards were too broad in Sprint 1.** The early signal was that "component" cards hid several smaller tasks, making progress hard to see: the Sprint 1 board grouped work into large cards such as "Speech <-> text (STT + TTS)," "Location Tracking / Accessing Database," and "LLM API: text in / text out" ([`docs/sprint-board-sprint-1.svg`](docs/sprint-board-sprint-1.svg)). The team committed to breaking Kanban work into sub-issues in Sprint 2.
2. **Too much landed in `home_screen.dart`.** The team integrated quickly, but the home screen became the voice loop, map preview, POI selection, TTS/STT, and session state owner. The early signal was repeated merge pressure on one file. Next time, the team would extract Conversation Manager, Voice Interface, and POI selection earlier ([`app/lib/home_screen.dart`](app/lib/home_screen.dart), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md)).
3. **Jolli did not fit the repo workflow.** The team tried to connect it for process tracking, but the docs did not match the app structure, so syncing became overhead. Next time, the team would either commit screenshots/exported board artifacts or keep all planning evidence in GitHub issues and project boards ([`docs/sprint-1-testing.md`](docs/sprint-1-testing.md), [`docs/sprint-1-retro.md`](docs/sprint-1-retro.md)).

AI tools pulled their weight for setup-heavy and integration-heavy work: CI, Flutter/Firebase friction, Groq prompting, and debugging voice behavior. The team had to override or unwind AI output when it wrote tests too close to fake internals, when architecture prose drifted ahead of runtime reality, and when generated solutions assumed clean module boundaries that the sprint branch did not yet have.

**Section references:** [`docs/sprint-1-retro.md`](docs/sprint-1-retro.md), [`docs/sprint-2-retro.md`](docs/sprint-2-retro.md), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md), [`docs/sprint-board-sprint-1.svg`](docs/sprint-board-sprint-1.svg), [`app/lib/home_screen.dart`](app/lib/home_screen.dart).

## 6. Future work

1. **Production-safe AI proxy (sprint-sized).** Move Groq and OpenRouter calls behind a backend-for-frontend so API keys are not extractable from the client. This matters before any public release beyond course/TestFlight users.
2. **Extract the live conversation stack (afternoon-sized to sprint-sized).** Pull voice session state, POI selection, and Groq conversation logic out of `home_screen.dart` into tested services. This reduces merge risk and aligns runtime code with the W4 component model.
3. **Background geofencing and fatigue controls (research plus sprint-sized implementation).** Add opt-in background location, quiet windows, cooldowns, and dismissal memory. This is core to the original proactive-companion vision but requires careful privacy and battery handling.
4. **Maps deep links and route handoff (afternoon-sized).** Add Apple/Google Maps URLs when a user asks for directions. This completes an edge in the original architecture without building navigation in-house.
5. **Field testing and data quality loop (sprint-sized).** Walk with the app, log bad recommendations, verify POI records, and add a lightweight admin review flow. This matters because a confident audio guide is only trustworthy if its place data is accurate.

**Section references:** [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md), [`app/.env.example`](app/.env.example), [`app/lib/home_screen.dart`](app/lib/home_screen.dart), [`geo-poi-database/`](geo-poi-database/), [`architecture/architecture.md`](architecture/architecture.md).

## 7. Advice to future CSEN 174 teams

1. Keep every sprint artifact in the repo or link it from the repo the day you create it.
2. Do not let the demo path grow inside one giant screen just because it is faster that week.
3. Use AI to get unstuck, but make it prove its work through repo-specific tests, links, and diffs.

**Section references:** [`docs/sprint-1-testing.md`](docs/sprint-1-testing.md), [`docs/sprint-1-retro.md`](docs/sprint-1-retro.md), [`docs/sprint-2-retro.md`](docs/sprint-2-retro.md), [`docs/architecture-retrospective.md`](docs/architecture-retrospective.md).
