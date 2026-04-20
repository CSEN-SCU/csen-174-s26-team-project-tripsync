import { useState } from "react";

const MIN_PW = 8;

export default function SignInScreen({ mode, onSwitchMode, onBack, onSubmit }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState(null);

  const isSignUp = mode === "signup";

  const submit = async (e) => {
    e.preventDefault();
    setError(null);
    const eTrim = email.trim();
    if (!eTrim || !eTrim.includes("@")) {
      setError("Enter a valid email.");
      return;
    }
    if (password.length < MIN_PW) {
      setError(`Password must be at least ${MIN_PW} characters.`);
      return;
    }
    setSubmitting(true);
    try {
      await onSubmit({ mode, email: eTrim, password });
    } catch (err) {
      setError(err?.message || "Something went wrong.");
    } finally {
      setSubmitting(false);
    }
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
        <h1 style={{ margin: "0 0 14px", fontSize: 24, fontWeight: 700 }}>
          {isSignUp ? "Create account" : "Sign in"}
        </h1>

        <div
          style={{
            display: "flex",
            gap: 0,
            marginBottom: 18,
            borderRadius: 10,
            border: "1px solid var(--border)",
            overflow: "hidden",
            fontSize: 13,
          }}
        >
          <button
            type="button"
            onClick={() => {
              onSwitchMode("signin");
              setError(null);
            }}
            style={{
              flex: 1,
              padding: "10px 12px",
              border: "none",
              fontWeight: 600,
              cursor: "pointer",
              background: !isSignUp ? "rgba(244,185,66,0.2)" : "transparent",
              color: "var(--text)",
            }}
          >
            Sign in
          </button>
          <button
            type="button"
            onClick={() => {
              onSwitchMode("signup");
              setError(null);
            }}
            style={{
              flex: 1,
              padding: "10px 12px",
              border: "none",
              borderLeft: "1px solid var(--border)",
              fontWeight: 600,
              cursor: "pointer",
              background: isSignUp ? "rgba(244,185,66,0.2)" : "transparent",
              color: "var(--text)",
            }}
          >
            Sign up
          </button>
        </div>

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
            Password ({MIN_PW}+ characters)
            <input
              type="password"
              autoComplete={isSignUp ? "new-password" : "current-password"}
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

          {error && (
            <p style={{ margin: "14px 0 0", fontSize: 13, color: "var(--danger)", lineHeight: 1.45 }}>{error}</p>
          )}

          <p style={{ margin: "14px 0 0", fontSize: 12, color: "var(--muted)", lineHeight: 1.5 }}>
            {isSignUp
              ? "Sign up stores your account in the backend SQLite file (orbit_kieran.db). It survives restarting the demo."
              : "Sign in loads your saved itineraries from the database. Keep the backend running on port 8010 (or set VITE_API_URL)."}
          </p>

          <button
            type="submit"
            disabled={submitting}
            style={{
              width: "100%",
              marginTop: 18,
              border: "none",
              borderRadius: 10,
              padding: "13px 16px",
              fontWeight: 600,
              background: "linear-gradient(135deg, var(--accent), #e09a1f)",
              color: "#1a1204",
              opacity: submitting ? 0.75 : 1,
            }}
          >
            {submitting ? "Please wait…" : isSignUp ? "Create account" : "Sign in"}
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
