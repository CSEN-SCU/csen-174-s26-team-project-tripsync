# Sprint 2 Retrospective

## Celebrate

Sprint 2 was about turning Sprint 1 pieces into something you could run on a phone. For most of the sprint the app was still basically one screen: landing page, then a home view with location and voice. Auth, onboarding, and the tab shell only landed in the last week.

Everyone shipped something that connected to the main app:

- **GP** hooked up the `llm_integration` package (guardrails, rate limiting) and routed signed-in users to a two-tab shell with Voice and LLM.
- **Daniel** added Firebase Auth, Google Sign-In, Firestore user profiles, and a sign-out confirmation dialog.
- **Rosalie** built the voice loop (Groq TTS, on-device speech recognition, speak-then-listen) and connected it to Firestore POI queries and multi-turn Groq conversation.
- **Kieran** shipped tap-to-select interest onboarding saved to Firestore and moved Firebase config out of the repo so CI loads keys from GitHub secrets.
- **Iker** added location permission and GPS on the home screen, then an OSM map preview in the location panel.

We also removed the old `prototypes/` folder and wrote up the architecture retrospective as the team consolidated on the single Flutter app in `app/`.

## AI tools reflection

Claude and Cursor helped most when we were wiring things together: Groq prompts, Firestore queries, merge conflicts, and voice bugs. It was faster to ask with the repo open than to dig through docs, especially on parts of the stack none of us had shipped before.

The downside was that everyone was building on the same home screen for most of the sprint, so the full flow only came together late. AI made merging easier, but it did not replace syncing up earlier. We also used it to draft the architecture retrospective, which surfaced debt we had been ignoring, like hardcoded interest tags and two separate Groq code paths.

Jolli still did not fit our workflow, so we kept tracking progress in GitHub and in-repo docs.

## Sprint 3 commitments

Two things we are committing to in Sprint 3:

1. **Wire onboarding preferences into the voice path.** Users pick interest chips during onboarding and we save them to Firestore, but the home screen still uses hardcoded tags for POI ranking. Sprint 3 will pass those saved preferences through to ranking and Groq prompts. *Card: [link TK]*
2. **Real-world testing on our phones.** We want to install the app, walk or drive around with it, and see how location, POI picks, and the voice loop hold up outside the lab. Sprint 3 will make time for field testing and fix what breaks in actual use. *Card: [link TK]*
