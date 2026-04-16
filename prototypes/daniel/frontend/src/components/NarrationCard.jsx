export default function NarrationCard({ poiName, speaking, onReplay, onStop }) {
  return (
    <div style={styles.card}>
      <div style={styles.header}>
        <div style={styles.poiName}>{poiName}</div>
        <button
          onClick={speaking ? onStop : onReplay}
          style={styles.audioBtn}
          title={speaking ? "Stop" : "Replay"}
        >
          {speaking ? (
            <span style={styles.audioWaves}>
              <span style={styles.wave} />
              <span style={{ ...styles.wave, animationDelay: "0.2s", height: 16 }} />
              <span style={{ ...styles.wave, animationDelay: "0.4s" }} />
            </span>
          ) : (
            "🔊"
          )}
        </button>
      </div>
    </div>
  );
}

const styles = {
  card: {
    padding: "10px 12px",
    borderRadius: "var(--radius-md)",
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
  },
  header: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
  },
  poiName: {
    fontSize: 14,
    fontWeight: 600,
    color: "var(--accent)",
  },
  audioBtn: {
    width: 36,
    height: 36,
    borderRadius: "50%",
    background: "var(--accent-soft)",
    border: "1px solid var(--accent-glow)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: 16,
    cursor: "pointer",
    color: "var(--text-primary)",
  },
  audioWaves: {
    display: "flex",
    alignItems: "center",
    gap: 2,
    height: 20,
  },
  wave: {
    width: 3,
    height: 12,
    borderRadius: 2,
    background: "var(--accent)",
    animation: "waveAnim 0.6s ease-in-out infinite alternate",
  },
};
