export default function IntroScreen({ onSignIn, onCreateAccount }) {
  return (
    <div
      style={{
        minHeight: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "32px 20px",
        textAlign: "center",
        background:
          "radial-gradient(ellipse 80% 60% at 50% 0%, rgba(244,185,66,0.12), transparent 55%), var(--bg)",
      }}
    >
      <div
        style={{
          maxWidth: 520,
          border: "1px solid var(--border)",
          borderRadius: "var(--radius)",
          padding: "32px 28px",
          background: "var(--panel)",
        }}
      >
        <p
          style={{
            margin: "0 0 8px",
            letterSpacing: "0.12em",
            textTransform: "uppercase",
            fontSize: "11px",
            color: "var(--muted)",
          }}
        >
          Prototype · Orbit
        </p>
        <h1 style={{ margin: "0 0 12px", fontSize: 28, fontWeight: 700 }}>
          Explore with an ambient guide
        </h1>
        <p style={{ margin: "0 0 20px", color: "var(--muted)", lineHeight: 1.55 }}>
          The map shows points of interest near Santa Clara. Turn on{" "}
          <strong style={{ color: "var(--text)" }}>passive mode</strong> for
          automatic heads-up audio when you get close, tap markers to listen anytime,
          and ask follow-up questions in the panel.
        </p>
        <ul
          style={{
            textAlign: "left",
            margin: "0 0 24px",
            paddingLeft: 20,
            color: "var(--muted)",
            lineHeight: 1.6,
            fontSize: 14,
          }}
        >
          <li>
            Places load live from <strong>OpenStreetMap</strong> (needs internet). They
            refresh as you move and about once a minute.
          </li>
          <li>
            With GPS, Orbit estimates your direction and speed to bias search slightly
            ahead of you.
          </li>
          <li>Allow location for real wandering, or click the map to drop a demo position.</li>
          <li>Audio uses your browser voice (no API keys required).</li>
        </ul>
        <button
          type="button"
          onClick={onSignIn}
          style={{
            width: "100%",
            border: "none",
            borderRadius: 10,
            padding: "14px 18px",
            fontWeight: 600,
            background: "linear-gradient(135deg, var(--accent), #e09a1f)",
            color: "#1a1204",
          }}
        >
          Sign in
        </button>
        <button
          type="button"
          onClick={onCreateAccount}
          style={{
            width: "100%",
            marginTop: 10,
            border: "1px solid var(--border)",
            borderRadius: 10,
            padding: "13px 18px",
            fontWeight: 600,
            background: "transparent",
            color: "var(--text)",
          }}
        >
          Create account
        </button>
      </div>
    </div>
  );
}
