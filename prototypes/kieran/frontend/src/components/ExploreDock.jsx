import { useState } from "react";

export default function ExploreDock({
  activePoi,
  narration,
  conversation,
  loading,
  error,
  speaking,
  onNext,
  nextDisabled,
  nextLabel,
  onReplay,
  onStop,
  onDismiss,
  onSend,
}) {
  const [draft, setDraft] = useState("");

  const submit = (e) => {
    e.preventDefault();
    const t = draft.trim();
    if (!t || !activePoi) return;
    onSend(t);
    setDraft("");
  };

  const lastAssistant = [...conversation]
    .reverse()
    .find((m) => m.role === "assistant");
  const previewText = lastAssistant?.content || narration || "";

  return (
    <div
      style={{
        flexShrink: 0,
        borderTop: "1px solid var(--border)",
        background: "rgba(11,16,32,0.96)",
        backdropFilter: "blur(10px)",
        padding: "12px 14px calc(12px + env(safe-area-inset-bottom, 0px))",
        boxShadow: "0 -8px 32px rgba(0,0,0,0.35)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          gap: 10,
          marginBottom: 8,
        }}
      >
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontSize: 10,
              letterSpacing: "0.12em",
              textTransform: "uppercase",
              color: "var(--muted)",
              marginBottom: 4,
            }}
          >
            Now exploring
          </div>
          <div
            style={{
              fontWeight: 700,
              fontSize: 17,
              lineHeight: 1.2,
              color: "var(--text)",
            }}
          >
            {activePoi?.name || "Tap the map"}
          </div>
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6, justifyContent: "flex-end" }}>
          <button
            type="button"
            onClick={onNext}
            disabled={nextDisabled}
            style={{
              ...btnPrimary,
              opacity: nextDisabled ? 0.4 : 1,
            }}
          >
            {nextLabel}
          </button>
          <button type="button" onClick={onReplay} disabled={!narration} style={btnGhost}>
            Replay
          </button>
          <button type="button" onClick={onStop} disabled={!speaking} style={btnGhost}>
            Stop
          </button>
          <button type="button" onClick={onDismiss} style={btnGhost}>
            Clear
          </button>
        </div>
      </div>

      {previewText && (
        <div
          style={{
            fontSize: 12,
            lineHeight: 1.45,
            color: "rgba(232,236,255,0.88)",
            maxHeight: 52,
            overflow: "hidden",
            marginBottom: 8,
          }}
        >
          {previewText.length > 240 ? `${previewText.slice(0, 237)}…` : previewText}
        </div>
      )}

      {error && (
        <div style={{ color: "var(--danger)", fontSize: 12, marginBottom: 8 }}>{error}</div>
      )}

      <form
        onSubmit={submit}
        style={{ display: "flex", gap: 8, alignItems: "center" }}
      >
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder={
            activePoi ? "Ask a follow-up…" : "Pick a map pin (or Filters → Places)"
          }
          disabled={!activePoi || loading}
          style={{
            flex: 1,
            minWidth: 0,
            borderRadius: 10,
            border: "1px solid var(--border)",
            padding: "10px 12px",
            fontSize: 14,
            background: "#121a30",
            color: "var(--text)",
          }}
        />
        <button
          type="submit"
          disabled={!activePoi || loading || !draft.trim()}
          style={{
            border: "none",
            borderRadius: 10,
            padding: "10px 16px",
            fontWeight: 600,
            fontSize: 14,
            background: "var(--accent)",
            color: "#1a1204",
            opacity: !activePoi || loading ? 0.45 : 1,
          }}
        >
          {loading ? "…" : "Send"}
        </button>
      </form>
    </div>
  );
}

const btnPrimary = {
  border: "none",
  borderRadius: 8,
  padding: "8px 14px",
  fontWeight: 600,
  fontSize: 13,
  background: "linear-gradient(135deg, var(--accent), #d9a020)",
  color: "#1a1204",
  cursor: "pointer",
};

const btnGhost = {
  borderRadius: 8,
  padding: "7px 10px",
  fontSize: 12,
  border: "1px solid var(--border)",
  background: "rgba(255,255,255,0.06)",
  color: "var(--text)",
  cursor: "pointer",
};
