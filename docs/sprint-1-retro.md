# Sprint 1 Retrospective

## Celebrate

Sprint 1 had concrete contributions from every member of the team:

- **GP** set up an Apple Developer account and deployed our app to TestFlight, getting our first installable build into testers' hands.
- **Daniel** stood up the skeleton app framework, giving the rest of the team a buildable shell to layer features onto.
- **Rosalie** created the CI/CD pipeline so commits are now built and tested automatically on every push.
- **Kieran** set up the Firebase database and seeded it with sample points of interest (POIs) for the geo-query layer to read against.
- **Iker** got Flutter installed and configured across the team's environments, unblocking the teammates who hadn't shipped Dart code before.

## AI tools reflection

Claude and Cursor helped significantly during Sprint 1, especially on the setup-heavy work. They saved valuable time researching how to set up Flutter, resolve dependency issues, and spin up the CI/CD pipeline — instead of hunting through scattered docs, we could ask in the context of our repo and get grounded answers. That was particularly useful for parts of the stack where no one on the team had prior experience.

The main friction came from Jolli. Its documentation didn't line up with how our app is actually structured, which made it difficult to use for keeping up to date with our progress. Rather than reducing overhead, syncing Jolli to the real state of the project added overhead, and we ended up reaching for tools that already fit our workflow.

## Sprint 2 commitments

Two improvements we are committing to in Sprint 2, each tracked as a Kanban card on our Sprint 2 board:

1. **Break Kanban tasks into sub-issues.** Our initial objectives and delegated tasks were too broad and ambitious to live as one Kanban card each. In Sprint 2 we will divide each task into sub-issues so progress is visible day to day and no card hides a small project inside it. *Card: [link TK]*
2. **Start linking the app's components together.** Sprint 1 produced separate pieces (skeleton app, voice, LLM seam, location engine, POI database). Sprint 2 will start wiring them into a single end-to-end flow, which will require more synchronous work between teammates. *Card: [link TK]*
