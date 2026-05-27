# Sprint 1 — Ethics Reflection

## Product Vision

Orbit helps people explore a city on their own terms by turning a map pin and a short taste profile into a small set of places they might actually visit — each with a clear "why you" explanation, not a generic list.

**Powered by:** real-time location-aware recommendation and natural language generation with conversational voice interaction.

## Stakeholders

### User stakeholder

- **Travelers using the app** — people exploring a new (or familiar) city who want curated, personalized recommendations.

### Non-user stakeholder

- **Local tour guide companies** — businesses whose livelihood depends on offering guided experiences in the same areas Orbit serves.
- **Businesses near recommended spots** — restaurants, shops, and attractions that may receive (or lose) foot traffic based on Orbit's recommendations.

## Potential Harms

### Harm 1 — Tracking precise user location data via phone GPS

- **Harm:** Continuously collecting precise GPS coordinates creates a privacy risk: location data can reveal sensitive patterns (home, work, places of worship, medical visits) and could be misused if leaked or shared.
- **Principle:** ACM Code of Ethics — *Public interest and safety*. "Software engineers must always prioritize the public's safety, privacy, and well-being above all else."
- **Mitigations:**
  - We updated our Firestore rules so that not everyone can access the database. Because we are still in active development, we plan to revise these rules again before any broader release.
  - We do **not** persistently store a user's location. We only read the user's coordinates at the moment the app requests nearby recommendations.
  - We do need a way to track a user's past visited locations for personalization. To minimize exposure, we will store those records keyed by an opaque user ID rather than directly identifiable information (see "Concrete change" below).

### Harm 2 — Recommending places that don't exist, are scams, or are unsafe

- **Harm:** If Orbit confidently sends a user to a place that is fake, closed, or unsafe, the user could waste time, lose money, or be put in physical danger. The conversational "why you" framing makes the recommendation feel more trustworthy, which amplifies the risk if the underlying data is wrong.
- **Principle:** ACM Code of Ethics — *Public interest and safety*. "Software engineers must always prioritize the public's safety, privacy, and well-being above all else."
- **Mitigations:**
  - All of the places currently in the app are local to us and have been manually vetted, so we know they are trustworthy and legitimate.
  - When we expand to new areas, we will not blindly trust new places. We will add a verification step — cross-referencing against authoritative sources (e.g. Google Places, official tourism boards) — before any new location is recommended to users.

### Harm 3 — Displacing local tour guides and human-led tourism

- **Harm:** Offering a "digital tour guide" experience can pull revenue and attention away from local tour guide companies and individual guides, which can erode local tourism economies and the cultural knowledge those guides preserve.
- **Principle:** ACM Code of Ethics — *Public interest and safety*. "Software engineers must always prioritize the public's safety, privacy, and well-being above all else."
- **Mitigations:**
  - We can introduce a **"local guide" user group** that allows knowledgeable locals to contribute recommendations for their community.
  - Local guides whose recommendations are visited would receive a portion of the revenue Orbit earns from that visit, so the product complements rather than replaces local expertise.

## One Concrete Change

Instead of storing a user's information and past visited places using their email or other personally identifiable information, we will track each user's history using a unique, opaque user ID (a hashed identifier). This identifier is not immediately tied back to the person, which adds another layer of privacy: even if the visit-history records were exposed, they could not be trivially linked to a real-world identity without the separate mapping.
