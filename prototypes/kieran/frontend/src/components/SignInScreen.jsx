import { useState } from "react";

export default function SignInScreen({ onBack, onSignedIn }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");

  const submit = (e) => {
    e.preventDefault();
    const eTrim = email.trim();
    onSignedIn(eTrim || "guest@orbit.local");
  };

  return (
    <div
      style={{
        minHeight: "100%",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "32px 20px",
        background:
          "radial-gradient(ellipse 80% 50% at 50% 0%, rgba(56,189,248,0.12), transparent 55%), var(--bg)",
      }}
    >
      <div
        style={{
          width: "100%",
          maxWidth: 400,
          border: "1px solid var(--border)",
          borderRadius: "var(--radius)",
          padding: "28px 24px",
          background: "var(--panel)",
        }}
      >
        <p
          style={{
            margin: "0 0 6px",
            letterSpacing: "0.12em",
            textTransform: "uppercase",
            fontSize: 11,
            color: "var(--muted)",
          }}
        >
          Orbit
        </p>
        <h1 style={{ margin: "0 0 18px", fontSize: 24, fontWeight: 700 }}>Sign in</h1>
        <form onSubmit={submit}>
          <label style={{ display: "block", fontSize: 12, color: "var(--muted)", marginBottom: 6 }}>
            Email
            <input
              type="email"
              autoComplete="username"
              value={email}
              onChange={(ev) => setEmail(ev.target.value)}
              placeholder="you@example.com"
              style={{
                display: "block",
                width: "100%",
                marginTop: 6,
                padding: "10px 12px",
                borderRadius: 10,
                border: "1px solid var(--border)",
                background: "rgba(0,0,0,0.25)",
                color: "var(--text)",
              }}
            />
          </label>
          <label
            style={{
              display: "block",
              fontSize: 12,
              color: "var(--muted)",
              marginTop: 14,
              marginBottom: 6,
            }}
          >
            Password
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(ev) => setPassword(ev.target.value)}
              placeholder="••••••••"
              style={{
                display: "block",
                width: "100%",
                marginTop: 6,
                padding: "10px 12px",
                borderRadius: 10,
                border: "1px solid var(--border)",
                background: "rgba(0,0,0,0.25)",
                color: "var(--text)",
              }}
            />
          </label>
          <p style={{ margin: "14px 0 0", fontSize: 12, color: "var(--muted)", lineHeight: 1.5 }}>
            Prototype only — no account is created. Use any email to continue.
          </p>
          <button
            type="submit"
            style={{
              width: "100%",
              marginTop: 18,
              border: "none",
              borderRadius: 10,
              padding: "13px 16px",
              fontWeight: 600,
              background: "linear-gradient(135deg, var(--accent), #e09a1f)",
              color: "#1a1204",
            }}
          >
            Sign in
          </button>
          <button
            type="button"
            onClick={onBack}
            style={{
              width: "100%",
              marginTop: 10,
              border: "1px solid var(--border)",
              borderRadius: 10,
              padding: "11px 16px",
              fontWeight: 500,
              background: "transparent",
              color: "var(--muted)",
            }}
          >
            Back
          </button>
        </form>
      </div>
    </div>
  );
}
