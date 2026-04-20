export default function IntroScreen({ health, onStart, onJoin }) {
  const groqReady = health?.groq_configured;
  return (
    <div className="screen">
      <div className="intro">
        <div className="hero">
          <div className="mark" role="img" aria-label="compass">
            🧭
          </div>
          <h1>Pick your next stop, as a group.</h1>
          <p>
            Orbit Together is a shared trip-planning room for friends who can't
            agree on what to do next. Everyone joins with one code, ticks what
            they're into, and Orbit surfaces 4–5 nearby spots — with a personal
            <em> "why YOU"</em> line for each of you.
          </p>
        </div>

        <div className="grid">
          <section>
            <div className="kicker">What it is</div>
            <h2>A neutral third voice</h2>
            <p className="muted small" style={{ marginTop: 4 }}>
              Part of the Orbit product vision: an AI-powered interactive travel
              guide. This prototype explores Orbit as a <strong>group</strong>{" "}
              experience instead of a solo one — the "Sync" in TripSync, taken
              literally.
            </p>
            <hr className="hr" />
            <div className="kicker">Who it's for</div>
            <div className="persona-strip">
              <div className="persona-chip">
                <strong>Priya</strong>the planner with the Google Doc
              </div>
              <div className="persona-chip">
                <strong>Marcus</strong>hungry, tired, decision-averse
              </div>
              <div className="persona-chip">
                <strong>Leah</strong>picky foodie, no tourist traps
              </div>
            </div>
            <p className="muted small" style={{ marginTop: 8 }}>
              See <code>storyboard.md</code> in the prototype folder for the
              full arc.
            </p>
          </section>

          <section>
            <div className="kicker">How to demo it</div>
            <ol style={{ paddingLeft: "1.1rem", margin: 0, color: "var(--ink-soft)" }}>
              <li>
                Tap <strong>Start a session</strong>, pick a city, give yourself
                a name + interests.
              </li>
              <li>
                Copy the 4-character code. Open a <em>second</em> browser window
                (or hand your phone to a friend) and tap{" "}
                <strong>Join a session</strong>.
              </li>
              <li>
                Once everyone's in, tap <strong>Get group picks</strong>. Each
                card shows a tailored line per person.
              </li>
              <li>
                React ❤️ / 🤔 / 👎. When the group converges, pick{" "}
                <strong>Let's go here</strong> and Orbit narrates the walk over.
              </li>
            </ol>

            <hr className="hr" />

            <div className="row" style={{ gap: "0.6rem", flexWrap: "wrap" }}>
              <button className="primary" onClick={onStart}>
                Start a session →
              </button>
              <button onClick={onJoin}>Join with a code</button>
            </div>

            <p className="muted small" style={{ marginTop: 10 }}>
              {health == null ? (
                <>Checking backend…</>
              ) : groqReady ? (
                <>
                  <span className="badge">AI live</span> &nbsp;Groq key detected —
                  POI picks + narration are generated per group.
                </>
              ) : (
                <>
                  <span className="badge dim">seed mode</span> &nbsp;No{" "}
                  <code>GROQ_API_KEY</code> in <code>backend/.env</code>. Demo
                  still runs with curated seed POIs for Lisbon, Barcelona, SF,
                  NYC.
                </>
              )}
            </p>
          </section>
        </div>
      </div>
    </div>
  );
}
