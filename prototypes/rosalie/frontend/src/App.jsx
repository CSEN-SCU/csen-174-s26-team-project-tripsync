import { useCallback, useEffect, useRef, useState } from "react";
import IntroScreen from "./components/IntroScreen.jsx";
import RouteMap from "./components/RouteMap.jsx";

const PRESETS = [
  { label: "Canal bend (Herengracht)", lat: 52.3708, lng: 4.8895 },
  { label: "Near Begijnhof", lat: 52.3692, lng: 4.889 },
  { label: "Westerkerk edge", lat: 52.3744, lng: 4.884 },
  { label: "Nine Streets", lat: 52.3696, lng: 4.8865 },
];

const INTERESTS = ["history", "quiet corners", "small shops", "canals"];

async function parseError(res) {
  try {
    const j = await res.json();
    if (j?.detail) return typeof j.detail === "string" ? j.detail : JSON.stringify(j.detail);
  } catch {
    /* ignore */
  }
  return res.statusText || "Request failed";
}

export default function App() {
  const [phase, setPhase] = useState("intro");
  const [lat, setLat] = useState(PRESETS[0].lat);
  const [lng, setLng] = useState(PRESETS[0].lng);
  const [excludeIds, setExcludeIds] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [session, setSession] = useState(null);
  const [showMap, setShowMap] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [followupQ, setFollowupQ] = useState("");
  const [followupLoading, setFollowupLoading] = useState(false);
  const [followup, setFollowup] = useState(null);
  const audioRef = useRef(null);

  const stopAudio = useCallback(() => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current = null;
    }
    setPlaying(false);
  }, []);

  useEffect(() => () => stopAudio(), [stopAudio]);

  const playDataUrl = useCallback(
    (dataUrl) => {
      stopAudio();
      const a = new Audio(dataUrl);
      audioRef.current = a;
      setPlaying(true);
      a.onended = () => {
        setPlaying(false);
        audioRef.current = null;
      };
      a.onerror = () => {
        setPlaying(false);
        audioRef.current = null;
      };
      a.play().catch(() => setPlaying(false));
    },
    [stopAudio]
  );

  const requestNudge = async ({ excludeLast }) => {
    setError(null);
    setFollowup(null);
    setLoading(true);
    try {
      let nextExclude = [...excludeIds];
      if (excludeLast && session?.place?.id) {
        nextExclude = [...nextExclude, session.place.id];
      }
      const res = await fetch("/api/nudge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          lat,
          lng,
          exclude_ids: nextExclude,
          interests: INTERESTS,
        }),
      });
      if (!res.ok) {
        setError(await parseError(res));
        setLoading(false);
        return;
      }
      const data = await res.json();
      setSession(data);
      setExcludeIds(nextExclude);
      setShowMap(false);
      playDataUrl(data.audio);
    } catch (e) {
      setError(e?.message || "Network error — is the API running on port 8020?");
    } finally {
      setLoading(false);
    }
  };

  const submitFollowup = async () => {
    if (!session?.place || !followupQ.trim()) return;
    setFollowupLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/followup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          place_id: session.place.id,
          place_name: session.place.name,
          category: session.place.category,
          facts: session.place.facts,
          question: followupQ.trim(),
        }),
      });
      if (!res.ok) {
        setError(await parseError(res));
        setFollowupLoading(false);
        return;
      }
      const data = await res.json();
      setFollowup(data);
      playDataUrl(data.audio);
    } catch (e) {
      setError(e?.message || "Follow-up failed");
    } finally {
      setFollowupLoading(false);
    }
  };

  return (
    <div className="app-shell">
      <div className="grain" aria-hidden />
      {phase === "intro" ? (
        <IntroScreen onBegin={() => setPhase("listen")} />
      ) : (
        <div className="panel">
          <div className="panel-inner">
            <p className="label">Sofia’s walk (simulated) · Amsterdam</p>
            <h2 style={{ margin: "0.2rem 0 0.6rem", fontSize: "1.75rem", color: "var(--cream)" }}>
              Ears first. Map on purpose.
            </h2>
            <p style={{ margin: "0 0 0.85rem", color: "rgba(250,246,239,0.78)", lineHeight: 1.5, fontSize: "0.95rem" }}>
              Place yourself where Sofia might be; that stand-in drives which highlight is nearest. We only draw the map
              if you want walking context.
            </p>

            <p className="label" style={{ marginTop: "0.75rem" }}>
              Quick stand-ins
            </p>
            <div className="preset-row">
              {PRESETS.map((p) => (
                <button
                  key={p.label}
                  type="button"
                  className="preset-chip"
                  onClick={() => {
                    setLat(p.lat);
                    setLng(p.lng);
                  }}
                >
                  {p.label}
                </button>
              ))}
            </div>

            <p className="label" style={{ marginTop: "0.85rem" }}>
              Coordinates (decimal degrees)
            </p>
            <div className="coord-grid">
              <input
                type="number"
                step="0.0001"
                value={lat}
                onChange={(e) => setLat(parseFloat(e.target.value))}
                className="coord-input"
                aria-label="Latitude"
              />
              <input
                type="number"
                step="0.0001"
                value={lng}
                onChange={(e) => setLng(parseFloat(e.target.value))}
                className="coord-input"
                aria-label="Longitude"
              />
            </div>

            {error ? <div className="error">{error}</div> : null}

            <div style={{ marginTop: "1rem" }}>
              <button type="button" className="btn-primary" disabled={loading} onClick={() => requestNudge({ excludeLast: false })}>
                {loading ? "Calling Orbit…" : "Hear a nearby highlight"}
              </button>
              <button
                type="button"
                className="btn-ghost"
                disabled={loading || !session}
                onClick={() => requestNudge({ excludeLast: true })}
              >
                Suggest a different spot
              </button>
            </div>

            {session ? (
              <div style={{ marginTop: "1.1rem" }}>
                <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "0.75rem" }}>
                  <div>
                    <p className="label">Now surfacing</p>
                    <h3 style={{ margin: 0, color: "var(--cream)", fontSize: "1.35rem" }}>{session.place.name}</h3>
                    <p style={{ margin: "0.25rem 0 0", color: "rgba(250,246,239,0.65)", fontSize: "0.9rem" }}>
                      ~{session.walk_minutes} min walk · {session.place.category}
                    </p>
                  </div>
                  {playing ? (
                    <div className="wave" aria-label="Playing audio">
                      <span />
                      <span />
                      <span />
                      <span />
                    </div>
                  ) : null}
                </div>

                <p
                  style={{
                    margin: "0.75rem 0 0",
                    color: "rgba(250,246,239,0.88)",
                    lineHeight: 1.55,
                    fontSize: "0.98rem",
                  }}
                >
                  {session.script}
                </p>

                <button type="button" className="btn-ghost" style={{ marginTop: "0.75rem" }} onClick={() => playDataUrl(session.audio)}>
                  Replay audio
                </button>

                <p className="label" style={{ marginTop: "1rem" }}>
                  Ask a follow-up (still no map needed)
                </p>
                <textarea
                  placeholder='e.g. "What should I notice when I get there?"'
                  value={followupQ}
                  onChange={(e) => setFollowupQ(e.target.value)}
                />
                <button
                  type="button"
                  className="btn-primary"
                  style={{ marginTop: "0.55rem" }}
                  disabled={followupLoading || !followupQ.trim()}
                  onClick={submitFollowup}
                >
                  {followupLoading ? "Thinking…" : "Ask & listen"}
                </button>

                {followup ? (
                  <p style={{ margin: "0.75rem 0 0", color: "rgba(250,246,239,0.88)", lineHeight: 1.55 }}>
                    {followup.answer}
                  </p>
                ) : null}

                <button
                  type="button"
                  className="btn-primary"
                  style={{ marginTop: "1rem", background: "linear-gradient(135deg,#134a5c,#0c2f38)" }}
                  onClick={() => setShowMap((s) => !s)}
                >
                  {showMap ? "Hide walking context" : "Show how to get there"}
                </button>

                {showMap ? (
                  <RouteMap userLat={lat} userLng={lng} placeLat={session.place.lat} placeLng={session.place.lng} />
                ) : null}
              </div>
            ) : null}

            <button type="button" className="btn-ghost" style={{ marginTop: "1.25rem" }} onClick={() => setPhase("intro")}>
              Back to intro
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
