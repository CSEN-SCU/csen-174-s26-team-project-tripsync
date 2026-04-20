export default function IntroScreen({ onBegin }) {
  return (
    <div className="panel" style={{ overflow: "hidden" }}>
      <div className="intro-hero">
        <p className="label">Orbit · Rosalie prototype</p>
        <h1>Listen first. Navigate only when you mean to.</h1>
        <p>
          Meet <strong>Sofia Reyes</strong> — 24, American, in Amsterdam to explore more spontaneously without getting
          stuck in her phone. Orbit uses your simulated spot in her shoes, speaks one short nudge about something
          worth walking to, and only opens a map when you decide to head there.
        </p>
        <ul className="intro-list">
          <li>
            <strong>Try it:</strong> pick a canal-side stand-in location, tap <em>Hear a nearby highlight</em>.
          </li>
          <li>
            <strong>Go deeper:</strong> ask a follow-up — answers are grounded on the place card we show (still no map
            required).
          </li>
          <li>
            <strong>Wayfinding:</strong> tap <em>Show how to get there</em> to reveal the map.
          </li>
        </ul>
      </div>
      <div className="panel-inner" style={{ paddingTop: 0 }}>
        <button type="button" className="btn-primary" onClick={onBegin}>
          Enter the listening flow
        </button>
      </div>
    </div>
  );
}
