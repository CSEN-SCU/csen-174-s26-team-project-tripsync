import { useState } from "react";
import SessionMap from "./SessionMap.jsx";
import POIFeed from "./POIFeed.jsx";
import DestinationBanner from "./DestinationBanner.jsx";
import InterestPicker, { INTEREST_CATALOG } from "./InterestPicker.jsx";

export default function SessionScreen({ state, me, refreshing, actions }) {
  const [copied, setCopied] = useState(false);
  const [recommending, setRecommending] = useState(false);
  const [editingMe, setEditingMe] = useState(false);

  const copyInvite = async () => {
    const url = `${window.location.origin}${window.location.pathname}#/s/${state.code}`;
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      window.prompt("Copy this join URL:", url);
    }
  };

  const runRecommend = async () => {
    setRecommending(true);
    try {
      await actions.recommend();
    } finally {
      setRecommending(false);
    }
  };

  return (
    <div className="session">
      <aside className="pane">
        <div className="row" style={{ marginBottom: 8 }}>
          <div>
            <div className="kicker">Invite</div>
            <div className="row" style={{ gap: 8 }}>
              <span className="code-pill">{state.code}</span>
              <button className="ghost small" onClick={copyInvite}>
                {copied ? "✓ copied" : "copy link"}
              </button>
            </div>
          </div>
        </div>

        <div className="kicker" style={{ marginTop: 6 }}>
          Who's in · {state.members.length}
        </div>
        <div className="member-bar">
          {state.members.map((m) => {
            const isMe = me && me.id === m.id;
            return (
              <span key={m.id} className={`member-pill${isMe ? " me" : ""}`}>
                <span className="avatar">{m.avatar || "🙂"}</span>
                <span>
                  {m.name}
                  {isMe ? " (you)" : ""}
                </span>
              </span>
            );
          })}
        </div>

        {me && (
          <div
            className="card"
            style={{
              padding: "0.8rem 0.9rem",
              marginBottom: 12,
              maxWidth: "none",
            }}
          >
            <div className="row" style={{ alignItems: "baseline" }}>
              <div className="kicker" style={{ margin: 0 }}>
                You
              </div>
              <button
                className="ghost small"
                style={{ marginLeft: "auto" }}
                onClick={() => setEditingMe((v) => !v)}
              >
                {editingMe ? "done" : "edit"}
              </button>
            </div>
            {!editingMe ? (
              <>
                <div style={{ fontWeight: 500, marginTop: 4 }}>
                  {me.avatar} {me.name}
                </div>
                <div className="small muted">
                  {(me.interests && me.interests.length)
                    ? INTEREST_CATALOG.filter((i) => me.interests.includes(i.id))
                        .map((i) => `${i.emoji} ${i.label}`)
                        .join(" · ")
                    : "No interests picked yet — hit edit"}
                </div>
                {me.vibe ? (
                  <div className="small muted" style={{ marginTop: 4 }}>
                    Vibe: {me.vibe}
                  </div>
                ) : null}
              </>
            ) : (
              <div className="stack" style={{ marginTop: 8 }}>
                <input
                  value={me.name}
                  onChange={(e) => actions.updateMe({ name: e.target.value })}
                />
                <InterestPicker
                  value={me.interests || []}
                  onChange={(next) => actions.updateMe({ interests: next })}
                />
                <input
                  placeholder="Vibe one-liner (optional)"
                  value={me.vibe || ""}
                  maxLength={120}
                  onChange={(e) => actions.updateMe({ vibe: e.target.value })}
                />
              </div>
            )}
          </div>
        )}

        <div className="row" style={{ marginBottom: 6 }}>
          <div className="kicker" style={{ margin: 0 }}>
            Group picks
          </div>
          <span className="muted small" style={{ marginLeft: "auto" }}>
            {refreshing ? "syncing…" : "live"}
          </span>
        </div>

        <POIFeed state={state} me={me} actions={actions} />

        <hr className="hr" />
        <p className="small muted">
          Why this is different from a solo planner: everyone's on the same
          map, same list, same code. One tap reveals who's ❤️ and who's 👎 —
          consensus surfaces naturally instead of through a group chat
          argument.
        </p>
      </aside>

      <main className="stage">
        <SessionMap state={state} me={me} />
        <div className="dock">
          {state.destination ? (
            <DestinationBanner state={state} actions={actions} />
          ) : (
            <div className="row" style={{ gap: "0.6rem", flexWrap: "wrap" }}>
              <div style={{ flex: 1, minWidth: 240 }}>
                <div className="kicker">Next move</div>
                <div>
                  {state.pois.length === 0
                    ? "Pull 5 nearby picks tailored to the group."
                    : "Keep reacting, or regenerate with the current interests."}
                </div>
                <div className="small muted" style={{ marginTop: 4 }}>
                  {state.groq_configured
                    ? "Uses Groq llama-3.3-70b for per-person 'why YOU' lines."
                    : "Seed mode — curated POIs, template reasons. Set GROQ_API_KEY for live AI."}
                </div>
              </div>
              <div
                className="row"
                style={{ gap: "0.4rem", flexWrap: "wrap", marginLeft: "auto" }}
              >
                {state.pois.length > 0 && (
                  <button onClick={actions.softReset}>Clear picks</button>
                )}
                <button
                  className="primary"
                  disabled={recommending || state.members.length === 0}
                  onClick={runRecommend}
                >
                  {recommending
                    ? "Thinking…"
                    : state.pois.length === 0
                    ? "Get group picks →"
                    : "Regenerate picks"}
                </button>
              </div>
            </div>
          )}
        </div>
      </main>
    </div>
  );
}
