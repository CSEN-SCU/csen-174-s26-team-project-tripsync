import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api } from "./lib/api.js";
import IntroScreen from "./components/IntroScreen.jsx";
import CreateJoinFlow from "./components/CreateJoinFlow.jsx";
import SessionScreen from "./components/SessionScreen.jsx";

// Four views. We use plain state + hashchange for lightweight routing so the URL
// updates when you join a session — that way a gallery-walk visitor can share the
// session URL with their laptop neighbor.
const VIEWS = {
  INTRO: "intro",
  CREATE: "create",
  JOIN: "join",
  SESSION: "session",
};

const STORAGE_KEY = "orbit-together/v1";

function loadPersistent() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function savePersistent(data) {
  try {
    if (!data) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  } catch {
    /* ignore */
  }
}

function readHashCode() {
  const m = window.location.hash.match(/#?\/s\/([A-Z0-9]{4})/i);
  return m ? m[1].toUpperCase() : null;
}

export default function App() {
  const [view, setView] = useState(VIEWS.INTRO);
  const [health, setHealth] = useState(null);
  const [sessionCode, setSessionCode] = useState(null);
  const [memberId, setMemberId] = useState(null);
  const [state, setState] = useState(null);
  const [error, setError] = useState(null);
  const [refreshing, setRefreshing] = useState(false);

  const pollRef = useRef(null);

  // Health + bootstrap from URL hash or localStorage.
  useEffect(() => {
    api.health().then(setHealth).catch((e) => console.warn("health", e));
    const hashCode = readHashCode();
    const stored = loadPersistent();
    if (hashCode && stored && stored.sessionCode === hashCode) {
      setSessionCode(stored.sessionCode);
      setMemberId(stored.memberId);
      setView(VIEWS.SESSION);
    } else if (hashCode) {
      setSessionCode(hashCode);
      setView(VIEWS.JOIN);
    } else if (stored?.sessionCode && stored?.memberId) {
      // Offer to restore prior session silently.
      setSessionCode(stored.sessionCode);
      setMemberId(stored.memberId);
      setView(VIEWS.SESSION);
    }
  }, []);

  // Reflect current session code in the URL hash (shareable join link).
  useEffect(() => {
    if (view === VIEWS.SESSION && sessionCode) {
      const target = `#/s/${sessionCode}`;
      if (window.location.hash !== target) {
        window.history.replaceState(null, "", target);
      }
    } else if (view === VIEWS.INTRO) {
      if (window.location.hash) window.history.replaceState(null, "", window.location.pathname);
    }
  }, [view, sessionCode]);

  const loadState = useCallback(
    async (code) => {
      if (!code) return;
      try {
        setRefreshing(true);
        const next = await api.getState(code);
        setState(next);
        setError(null);
      } catch (e) {
        // 404 means the session was nuked (e.g. between gallery visitors). Bail.
        if (e?.status === 404) {
          savePersistent(null);
          setSessionCode(null);
          setMemberId(null);
          setState(null);
          setView(VIEWS.INTRO);
          setError("That session was reset. Start a new one.");
        } else {
          setError(e.message || String(e));
        }
      } finally {
        setRefreshing(false);
      }
    },
    []
  );

  // Polling loop while inside a session — 2s cadence is enough for this demo.
  useEffect(() => {
    if (view !== VIEWS.SESSION || !sessionCode) {
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
      return;
    }
    loadState(sessionCode);
    pollRef.current = setInterval(() => loadState(sessionCode), 2000);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
      pollRef.current = null;
    };
  }, [view, sessionCode, loadState]);

  const enterSession = useCallback((code, newMemberId) => {
    setSessionCode(code);
    setMemberId(newMemberId);
    savePersistent({ sessionCode: code, memberId: newMemberId });
    setView(VIEWS.SESSION);
  }, []);

  const leaveSession = useCallback(() => {
    savePersistent(null);
    setSessionCode(null);
    setMemberId(null);
    setState(null);
    setView(VIEWS.INTRO);
  }, []);

  const me = useMemo(() => {
    if (!state || !memberId) return null;
    return state.members.find((m) => m.id === memberId) || null;
  }, [state, memberId]);

  // ----- actions passed to SessionScreen -----

  const actions = useMemo(
    () => ({
      refresh: () => sessionCode && loadState(sessionCode),
      recommend: async () => {
        if (!sessionCode) return;
        try {
          const next = await api.recommend(sessionCode);
          setState(next);
        } catch (e) {
          setError(e.message);
        }
      },
      react: async (poiId, kind) => {
        if (!memberId) return;
        try {
          const next = await api.react({ poiId, memberId, kind });
          setState(next);
        } catch (e) {
          setError(e.message);
        }
      },
      pick: async (poiId) => {
        if (!sessionCode) return;
        try {
          const next = await api.pick(sessionCode, poiId);
          setState(next);
        } catch (e) {
          setError(e.message);
        }
      },
      updateMe: async (patch) => {
        if (!memberId) return;
        try {
          const next = await api.updateMember(memberId, patch);
          setState(next);
        } catch (e) {
          setError(e.message);
        }
      },
      softReset: async () => {
        if (!sessionCode) return;
        try {
          const next = await api.softReset(sessionCode);
          setState(next);
        } catch (e) {
          setError(e.message);
        }
      },
      leave: leaveSession,
    }),
    [sessionCode, memberId, loadState, leaveSession]
  );

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <span className="mark" role="img" aria-label="compass">
            🧭
          </span>
          <span>Orbit Together</span>
          <span className="dim small">by Iker · TripSync</span>
        </div>
        <div className="row">
          {state && view === VIEWS.SESSION ? (
            <>
              <span className="dim small">
                {state.city} · {state.members.length} joined ·{" "}
                {state.ai_source === "groq" ? (
                  <span className="badge">AI live</span>
                ) : (
                  <span className="badge dim">seed mode</span>
                )}
              </span>
              <span
                className="code-pill"
                title="Session code — share this with friends"
              >
                {state.code}
              </span>
              <button className="ghost" onClick={leaveSession}>
                Leave
              </button>
            </>
          ) : (
            <span className="dim small">
              Week 3 divergent prototype · CSEN 174
            </span>
          )}
        </div>
      </header>

      {error && (
        <div
          className="card"
          style={{
            margin: "0.8rem auto 0",
            maxWidth: 780,
            borderColor: "#d97b5b",
            background: "#fff4ec",
          }}
        >
          <strong style={{ color: "var(--accent)" }}>Hiccup:</strong>{" "}
          <span className="muted">{error}</span>{" "}
          <button
            className="ghost small"
            onClick={() => setError(null)}
            style={{ marginLeft: "auto" }}
          >
            dismiss
          </button>
        </div>
      )}

      {view === VIEWS.INTRO && (
        <IntroScreen
          health={health}
          onStart={() => setView(VIEWS.CREATE)}
          onJoin={() => setView(VIEWS.JOIN)}
        />
      )}

      {view === VIEWS.CREATE && (
        <CreateJoinFlow
          mode="create"
          defaultCode={sessionCode || ""}
          onCancel={() => setView(VIEWS.INTRO)}
          onSuccess={enterSession}
        />
      )}

      {view === VIEWS.JOIN && (
        <CreateJoinFlow
          mode="join"
          defaultCode={sessionCode || ""}
          onCancel={() => setView(VIEWS.INTRO)}
          onSuccess={enterSession}
        />
      )}

      {view === VIEWS.SESSION && state && (
        <SessionScreen
          state={state}
          me={me}
          refreshing={refreshing}
          actions={actions}
        />
      )}

      {view === VIEWS.SESSION && !state && (
        <div className="screen">
          <div className="card" style={{ textAlign: "center" }}>
            <p className="muted">Loading session {sessionCode}…</p>
          </div>
        </div>
      )}
    </div>
  );
}
