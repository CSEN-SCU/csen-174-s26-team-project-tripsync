import { useCallback, useEffect, useState } from "react";
import { getApiBase } from "../lib/apiConfig.js";

const btnSecondary = {
  borderRadius: 8,
  padding: "8px 12px",
  fontSize: 12,
  border: "1px solid var(--border)",
  background: "transparent",
  color: "var(--text)",
  cursor: "pointer",
};

export default function FriendsPanel({ userId, onBack }) {
  const [friends, setFriends] = useState([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(null);
  const [addEmail, setAddEmail] = useState("");
  const [adding, setAdding] = useState(false);

  const load = useCallback(async () => {
    if (userId == null) {
      setLoading(false);
      setErr(
        "You are not signed in (no saved session). Use Sign in with the backend running, or Create account if you are new."
      );
      return;
    }
    setLoading(true);
    setErr(null);
    try {
      const res = await fetch(`${getApiBase()}/users/${userId}/friends`);
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.detail || `Failed (${res.status})`);
      }
      const data = await res.json();
      setFriends(Array.isArray(data) ? data : []);
    } catch (e) {
      setErr(e?.message || "Could not load friends");
      setFriends([]);
    } finally {
      setLoading(false);
    }
  }, [userId]);

  useEffect(() => {
    load();
  }, [load]);

  const addFriend = async (e) => {
    e.preventDefault();
    const em = addEmail.trim();
    if (!em || userId == null) return;
    setAdding(true);
    setErr(null);
    try {
      const res = await fetch(`${getApiBase()}/users/${userId}/friends`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: em }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(
          typeof body.detail === "string" ? body.detail : JSON.stringify(body.detail) || "Request failed"
        );
      }
      setAddEmail("");
      await load();
    } catch (e) {
      setErr(e?.message || "Could not add friend");
    } finally {
      setAdding(false);
    }
  };

  const remove = async (friendUserId) => {
    if (userId == null) return;
    if (!window.confirm("Remove this connection?")) return;
    try {
      const res = await fetch(`${getApiBase()}/users/${userId}/friends/${friendUserId}`, { method: "DELETE" });
      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.detail || `Failed (${res.status})`);
      }
      await load();
    } catch (e) {
      setErr(e?.message || "Could not remove");
    }
  };

  return (
    <div
      style={{
        minHeight: "100%",
        display: "flex",
        flexDirection: "column",
        background: "var(--bg)",
        color: "var(--text)",
      }}
    >
      <header
        style={{
          flexShrink: 0,
          display: "flex",
          alignItems: "center",
          gap: 12,
          padding: "14px 16px",
          borderBottom: "1px solid var(--border)",
          background: "rgba(11,16,32,0.96)",
        }}
      >
        <button type="button" onClick={onBack} style={{ ...btnSecondary, flexShrink: 0 }}>
          ← Menu
        </button>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontSize: 11,
              color: "var(--muted)",
              textTransform: "uppercase",
              letterSpacing: "0.08em",
            }}
          >
            Social
          </div>
          <div style={{ fontWeight: 700, fontSize: 17 }}>Friends</div>
        </div>
      </header>

      <div style={{ flex: 1, overflow: "auto", padding: "16px 16px 28px", maxWidth: 520, margin: "0 auto", width: "100%" }}>
        <p style={{ margin: "0 0 16px", fontSize: 13, color: "var(--muted)", lineHeight: 1.55 }}>
          Connect with people who use Orbit with a different email. They must sign in once before they appear in search.
        </p>

        <section
          style={{
            marginBottom: 20,
            padding: 16,
            borderRadius: "var(--radius)",
            border: "1px solid var(--border)",
            background: "var(--panel)",
          }}
        >
          <h2 style={{ margin: "0 0 10px", fontSize: 15, fontWeight: 700 }}>Add by email</h2>
          <form onSubmit={addFriend} style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <input
              type="email"
              value={addEmail}
              onChange={(ev) => setAddEmail(ev.target.value)}
              placeholder="friend@example.com"
              style={{
                flex: "1 1 200px",
                minWidth: 0,
                padding: "10px 12px",
                borderRadius: 10,
                border: "1px solid var(--border)",
                background: "rgba(0,0,0,0.2)",
                color: "var(--text)",
              }}
            />
            <button
              type="submit"
              disabled={adding || !addEmail.trim()}
              style={{
                border: "none",
                borderRadius: 10,
                padding: "10px 16px",
                fontWeight: 600,
                background: "linear-gradient(135deg, var(--accent), #e09a1f)",
                color: "#1a1204",
                opacity: adding ? 0.7 : 1,
              }}
            >
              {adding ? "Adding…" : "Connect"}
            </button>
          </form>
        </section>

        {err && (
          <div style={{ marginBottom: 14, fontSize: 13, color: "var(--danger)", lineHeight: 1.45 }}>{err}</div>
        )}

        <section
          style={{
            padding: 16,
            borderRadius: "var(--radius)",
            border: "1px solid var(--border)",
            background: "var(--panel)",
          }}
        >
          <h2 style={{ margin: "0 0 12px", fontSize: 15, fontWeight: 700 }}>Your connections</h2>
          {loading ? (
            <div style={{ fontSize: 13, color: "var(--muted)" }}>Loading…</div>
          ) : friends.length === 0 ? (
            <div style={{ fontSize: 13, color: "var(--muted)" }}>No friends yet — add someone above.</div>
          ) : (
            <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
              {friends.map((f) => (
                <li
                  key={f.id}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                    padding: "12px 0",
                    borderBottom: "1px solid rgba(255,255,255,0.06)",
                  }}
                >
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 700 }}>{f.email}</div>
                  </div>
                  <button
                    type="button"
                    onClick={() => remove(f.id)}
                    style={{
                      ...btnSecondary,
                      fontSize: 11,
                      color: "var(--danger)",
                      borderColor: "rgba(248,113,113,0.35)",
                    }}
                  >
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
}
