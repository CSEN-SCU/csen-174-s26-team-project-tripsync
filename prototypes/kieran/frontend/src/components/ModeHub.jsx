export default function ModeHub({ displayName, onExplore, onManageItineraries, onFriends, onSignOut }) {
  const cardBase = {
    width: "100%",
    textAlign: "left",
    borderRadius: 12,
    padding: "20px 18px",
    border: "1px solid var(--border)",
    background: "rgba(255,255,255,0.04)",
    color: "var(--text)",
    cursor: "pointer",
    transition: "border-color 0.15s, background 0.15s",
  };

  return (
    <div
      style={{
        minHeight: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "28px 20px",
        background:
          "radial-gradient(ellipse 70% 45% at 50% 0%, rgba(244,185,66,0.1), transparent 50%), var(--bg)",
      }}
    >
      <div style={{ width: "100%", maxWidth: 440 }}>
        <p
          style={{
            margin: "0 0 6px",
            letterSpacing: "0.12em",
            textTransform: "uppercase",
            fontSize: 11,
            color: "var(--muted)",
          }}
        >
          Signed in
        </p>
        <h1 style={{ margin: "0 0 6px", fontSize: 26, fontWeight: 700 }}>Welcome back</h1>
        <p style={{ margin: "0 0 22px", color: "var(--muted)", fontSize: 14 }}>{displayName}</p>

        <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
          <button type="button" onClick={onExplore} style={cardBase}>
            <div style={{ fontSize: 11, color: "var(--accent)", fontWeight: 600, marginBottom: 6 }}>
              Walk & discover
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, marginBottom: 6 }}>Explore</div>
            <div style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.5 }}>
              Map, nearby places, passive heads-up narration, and chat — the experience you had before.
            </div>
          </button>

          <button type="button" onClick={onManageItineraries} style={cardBase}>
            <div style={{ fontSize: 11, color: "#7dd3fc", fontWeight: 600, marginBottom: 6 }}>
              Lists & stops
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, marginBottom: 6 }}>Manage itineraries</div>
            <div style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.5 }}>
              Create itineraries, add or remove specific things you want to do, and organize them into
              groups.
            </div>
          </button>

          <button type="button" onClick={onFriends} style={cardBase}>
            <div style={{ fontSize: 11, color: "#a78bfa", fontWeight: 600, marginBottom: 6 }}>
              People
            </div>
            <div style={{ fontSize: 18, fontWeight: 700, marginBottom: 6 }}>Friends</div>
            <div style={{ fontSize: 13, color: "var(--muted)", lineHeight: 1.5 }}>
              Link accounts by email so you can grow a travel circle (prototype — no shared itineraries yet).
            </div>
          </button>
        </div>

        <button
          type="button"
          onClick={onSignOut}
          style={{
            marginTop: 20,
            width: "100%",
            border: "none",
            background: "transparent",
            color: "var(--muted)",
            fontSize: 13,
            padding: 8,
          }}
        >
          Sign out
        </button>
      </div>
    </div>
  );
}
