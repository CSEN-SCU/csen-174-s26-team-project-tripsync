import { useRef, useEffect, useState } from "react";
import NarrationCard from "./NarrationCard";
import ActionButtons from "./ActionButtons";

export default function PhoneMockup({
  activePoi,
  narration,
  conversation,
  loading,
  error,
  interests,
  speaking,
  onTellMore,
  onDirections,
  onDismiss,
  onConverse,
  onReplay,
  onStopAudio,
}) {
  const scrollRef = useRef(null);
  const [input, setInput] = useState("");

  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [conversation]);

  const handleSend = (e) => {
    e.preventDefault();
    if (!input.trim() || !activePoi) return;
    onConverse(input.trim());
    setInput("");
  };

  return (
    <div style={styles.phoneFrame}>
      {/* Status bar */}
      <div style={styles.statusBar}>
        <span style={styles.time}>
          {new Date().toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          })}
        </span>
        <div style={styles.notch} />
        <div style={styles.statusIcons}>
          <span>📶</span>
          <span>🔋</span>
        </div>
      </div>

      {/* App header */}
      <div style={styles.appHeader}>
        <div style={styles.headerLeft}>
          <span style={styles.orbitIcon}>◎</span>
          <span style={styles.orbitTitle}>Orbit</span>
        </div>
        {activePoi && (
          <div style={styles.listeningBadge}>
            <span style={styles.listeningDot} />
            Listening
          </div>
        )}
      </div>

      {/* Interests */}
      <div style={styles.interestsBar}>
        {interests.map((i) => (
          <span key={i} style={styles.interestTag}>
            {i}
          </span>
        ))}
      </div>

      {/* Main content area */}
      <div ref={scrollRef} style={styles.contentArea}>
        {!activePoi && !loading && (
          <div style={styles.emptyState}>
            <div style={styles.emptyIcon}>◎</div>
            <div style={styles.emptyTitle}>Exploring...</div>
            <div style={styles.emptyDesc}>
              Drag the pin on the map to discover nearby points of interest.
              Orbit will notify you when something interesting is close.
            </div>
          </div>
        )}

        {loading && !narration && (
          <div style={styles.emptyState}>
            <div style={styles.spinner} />
            <div style={styles.emptyTitle}>Scanning nearby...</div>
          </div>
        )}

        {conversation.map((msg, i) => (
          <div
            key={i}
            style={{
              ...styles.messageBubble,
              ...(msg.role === "user" ? styles.userBubble : styles.assistantBubble),
            }}
          >
            {msg.role === "assistant" && (
              <div style={styles.bubbleHeader}>
                <span style={styles.bubbleIcon}>◎</span>
                <span style={styles.bubbleName}>Orbit</span>
              </div>
            )}
            <div style={styles.bubbleText}>{msg.content}</div>
          </div>
        ))}

        {loading && narration && (
          <div style={styles.typingIndicator}>
            <span style={styles.dot} />
            <span style={{ ...styles.dot, animationDelay: "0.2s" }} />
            <span style={{ ...styles.dot, animationDelay: "0.4s" }} />
          </div>
        )}

        {error && (
          <div style={styles.errorBubble}>
            <div style={{ fontWeight: 600, marginBottom: 4 }}>Connection issue</div>
            <div>{error}</div>
          </div>
        )}
      </div>

      {/* Narration card + actions */}
      {activePoi && (
        <div style={styles.bottomSection}>
          <NarrationCard
            poiName={activePoi.name}
            speaking={speaking}
            onReplay={onReplay}
            onStop={onStopAudio}
          />
          <ActionButtons
            onTellMore={onTellMore}
            onDirections={onDirections}
            onDismiss={onDismiss}
            disabled={loading}
          />
          <form onSubmit={handleSend} style={styles.inputRow}>
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask Orbit anything..."
              style={styles.input}
              disabled={loading}
            />
            <button
              type="submit"
              style={{
                ...styles.sendBtn,
                opacity: input.trim() && !loading ? 1 : 0.4,
              }}
              disabled={!input.trim() || loading}
            >
              ↑
            </button>
          </form>
        </div>
      )}

      {/* Home indicator */}
      <div style={styles.homeIndicator}>
        <div style={styles.homeBar} />
      </div>
    </div>
  );
}

const styles = {
  phoneFrame: {
    width: 375,
    height: "calc(100vh - 48px)",
    maxHeight: 812,
    background: "var(--bg-panel)",
    borderRadius: 44,
    border: "3px solid var(--border)",
    display: "flex",
    flexDirection: "column",
    overflow: "hidden",
    boxShadow: "0 0 60px rgba(0,0,0,0.5), 0 0 120px rgba(0,0,0,0.2)",
    position: "relative",
  },
  statusBar: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "12px 28px 4px",
    fontSize: 13,
    fontWeight: 600,
    color: "var(--text-primary)",
  },
  time: {
    fontSize: 14,
    fontWeight: 600,
  },
  notch: {
    width: 120,
    height: 28,
    background: "var(--bg-deep)",
    borderRadius: 20,
  },
  statusIcons: {
    display: "flex",
    gap: 4,
    fontSize: 12,
  },
  appHeader: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "12px 24px 8px",
  },
  headerLeft: {
    display: "flex",
    alignItems: "center",
    gap: 8,
  },
  orbitIcon: {
    fontSize: 22,
    color: "var(--accent)",
  },
  orbitTitle: {
    fontFamily: "var(--font-display)",
    fontSize: 22,
  },
  listeningBadge: {
    display: "flex",
    alignItems: "center",
    gap: 6,
    padding: "4px 12px",
    borderRadius: 100,
    background: "var(--green-soft)",
    color: "var(--green)",
    fontSize: 12,
    fontWeight: 600,
  },
  listeningDot: {
    width: 6,
    height: 6,
    borderRadius: "50%",
    background: "var(--green)",
    animation: "blink 1.5s infinite",
  },
  interestsBar: {
    display: "flex",
    gap: 6,
    padding: "4px 24px 12px",
    overflowX: "auto",
    flexShrink: 0,
  },
  interestTag: {
    padding: "3px 10px",
    borderRadius: 100,
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
    fontSize: 11,
    color: "var(--text-secondary)",
    whiteSpace: "nowrap",
    fontWeight: 500,
  },
  contentArea: {
    flex: 1,
    overflowY: "auto",
    padding: "8px 20px",
    display: "flex",
    flexDirection: "column",
    gap: 10,
  },
  emptyState: {
    flex: 1,
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    gap: 12,
    padding: 40,
  },
  emptyIcon: {
    fontSize: 48,
    color: "var(--accent)",
    opacity: 0.4,
  },
  emptyTitle: {
    fontSize: 16,
    fontWeight: 600,
    color: "var(--text-secondary)",
  },
  emptyDesc: {
    fontSize: 13,
    color: "var(--text-muted)",
    textAlign: "center",
    lineHeight: 1.6,
  },
  spinner: {
    width: 32,
    height: 32,
    border: "3px solid var(--border)",
    borderTopColor: "var(--accent)",
    borderRadius: "50%",
    animation: "spin 0.8s linear infinite",
  },
  messageBubble: {
    maxWidth: "90%",
    padding: "10px 14px",
    borderRadius: "var(--radius-md)",
    fontSize: 14,
    lineHeight: 1.6,
  },
  assistantBubble: {
    alignSelf: "flex-start",
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
  },
  userBubble: {
    alignSelf: "flex-end",
    background: "var(--accent)",
    color: "#0a0c10",
    borderRadius: "var(--radius-md)",
  },
  bubbleHeader: {
    display: "flex",
    alignItems: "center",
    gap: 6,
    marginBottom: 4,
  },
  bubbleIcon: {
    fontSize: 14,
    color: "var(--accent)",
  },
  bubbleName: {
    fontSize: 12,
    fontWeight: 600,
    color: "var(--accent)",
  },
  bubbleText: {
    fontSize: 14,
    lineHeight: 1.6,
  },
  typingIndicator: {
    display: "flex",
    gap: 4,
    padding: "10px 14px",
    alignSelf: "flex-start",
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: "50%",
    background: "var(--text-muted)",
    animation: "bounce 1.4s infinite ease-in-out",
  },
  errorBubble: {
    alignSelf: "flex-start",
    maxWidth: "90%",
    padding: "10px 14px",
    borderRadius: "var(--radius-md)",
    background: "var(--red-soft)",
    border: "1px solid var(--red)44",
    color: "var(--red)",
    fontSize: 13,
    lineHeight: 1.5,
  },
  bottomSection: {
    borderTop: "1px solid var(--border)",
    padding: "12px 16px",
    background: "var(--bg-panel)",
    display: "flex",
    flexDirection: "column",
    gap: 10,
    flexShrink: 0,
  },
  inputRow: {
    display: "flex",
    gap: 8,
  },
  input: {
    flex: 1,
    padding: "10px 14px",
    borderRadius: "var(--radius-lg)",
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
    color: "var(--text-primary)",
    fontSize: 14,
    fontFamily: "var(--font-body)",
    outline: "none",
  },
  sendBtn: {
    width: 40,
    height: 40,
    borderRadius: "50%",
    background: "var(--accent)",
    color: "#0a0c10",
    fontSize: 18,
    fontWeight: 700,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    transition: "opacity 0.15s ease",
    flexShrink: 0,
  },
  homeIndicator: {
    padding: "8px 0 6px",
    display: "flex",
    justifyContent: "center",
  },
  homeBar: {
    width: 140,
    height: 5,
    borderRadius: 100,
    background: "var(--text-muted)",
    opacity: 0.4,
  },
};
