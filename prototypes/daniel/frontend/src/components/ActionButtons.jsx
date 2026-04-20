export default function ActionButtons({ onTellMore, onDirections, onDismiss, disabled }) {
  return (
    <div style={styles.row}>
      <button
        style={{ ...styles.btn, ...styles.tellMore }}
        onClick={onTellMore}
        disabled={disabled}
      >
        <span style={styles.btnIcon}>✦</span>
        Tell Me More
      </button>
      <button
        style={{ ...styles.btn, ...styles.directions }}
        onClick={onDirections}
        disabled={disabled}
      >
        <span style={styles.btnIcon}>↗</span>
        Directions
      </button>
      <button
        style={{ ...styles.btn, ...styles.dismiss }}
        onClick={onDismiss}
        disabled={disabled}
      >
        <span style={styles.btnIcon}>✕</span>
      </button>
    </div>
  );
}

const styles = {
  row: {
    display: "flex",
    gap: 8,
  },
  btn: {
    flex: 1,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: 6,
    padding: "10px 8px",
    borderRadius: "var(--radius-sm)",
    fontSize: 12,
    fontWeight: 600,
    transition: "all 0.15s ease",
    cursor: "pointer",
  },
  btnIcon: {
    fontSize: 14,
  },
  tellMore: {
    background: "var(--accent-soft)",
    border: "1px solid var(--accent-glow)",
    color: "var(--accent)",
  },
  directions: {
    background: "var(--blue-soft)",
    border: "1px solid var(--blue)33",
    color: "var(--blue)",
  },
  dismiss: {
    flex: "0 0 42px",
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
    color: "var(--text-muted)",
  },
};
