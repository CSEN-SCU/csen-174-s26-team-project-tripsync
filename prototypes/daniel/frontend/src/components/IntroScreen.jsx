import { useState } from "react";

const FEATURES = [
  {
    icon: "🎧",
    title: "Audio-First",
    desc: "Orbit narrates your surroundings so you can keep your eyes on the road — or the view.",
  },
  {
    icon: "📍",
    title: "Location-Aware",
    desc: "As you move, Orbit detects interesting places nearby and tells you about them in real time.",
  },
  {
    icon: "💬",
    title: "Conversational",
    desc: "Ask follow-up questions, get directions, or dive deeper — like chatting with a local friend.",
  },
];

export default function IntroScreen({ onStart }) {
  const [hovering, setHovering] = useState(false);

  return (
    <div style={styles.container}>
      <div style={styles.grain} />
      <div style={styles.glowOrb1} />
      <div style={styles.glowOrb2} />

      <div style={styles.content}>
        <div style={styles.badge}>AI Travel Companion</div>

        <h1 style={styles.title}>
          <span style={styles.titleAccent}>Orbit</span>
        </h1>

        <p style={styles.subtitle}>
          Like a local guide riding shotgun.
        </p>

        <p style={styles.description}>
          Orbit surfaces hidden gems, tells you their stories, and answers your
          questions — all hands-free. Stop scrolling, start discovering.
        </p>

        <div style={styles.features}>
          {FEATURES.map((f) => (
            <div key={f.title} style={styles.featureCard}>
              <span style={styles.featureIcon}>{f.icon}</span>
              <div>
                <div style={styles.featureTitle}>{f.title}</div>
                <div style={styles.featureDesc}>{f.desc}</div>
              </div>
            </div>
          ))}
        </div>

        <button
          style={{
            ...styles.startBtn,
            ...(hovering ? styles.startBtnHover : {}),
          }}
          onMouseEnter={() => setHovering(true)}
          onMouseLeave={() => setHovering(false)}
          onClick={onStart}
        >
          Start Exploring
          <span style={styles.arrow}>→</span>
        </button>

        <p style={styles.hint}>
          Drag the pin on the map to simulate traveling. Orbit will tell you
          about interesting things nearby.
        </p>
      </div>
    </div>
  );
}

const styles = {
  container: {
    height: "100vh",
    width: "100vw",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    background: "var(--bg-deep)",
    position: "relative",
    overflow: "hidden",
  },
  grain: {
    position: "absolute",
    inset: 0,
    opacity: 0.03,
    backgroundImage: `url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)'/%3E%3C/svg%3E")`,
    pointerEvents: "none",
  },
  glowOrb1: {
    position: "absolute",
    width: 600,
    height: 600,
    borderRadius: "50%",
    background: "radial-gradient(circle, var(--accent-glow) 0%, transparent 70%)",
    top: "-15%",
    right: "-10%",
    pointerEvents: "none",
  },
  glowOrb2: {
    position: "absolute",
    width: 400,
    height: 400,
    borderRadius: "50%",
    background: "radial-gradient(circle, var(--blue-soft) 0%, transparent 70%)",
    bottom: "-10%",
    left: "-5%",
    pointerEvents: "none",
  },
  content: {
    position: "relative",
    zIndex: 1,
    maxWidth: 640,
    textAlign: "center",
    padding: "0 32px",
  },
  badge: {
    display: "inline-block",
    padding: "6px 16px",
    borderRadius: 100,
    background: "var(--accent-soft)",
    color: "var(--accent)",
    fontSize: 13,
    fontWeight: 600,
    letterSpacing: "0.04em",
    textTransform: "uppercase",
    marginBottom: 24,
    border: "1px solid var(--accent-glow)",
  },
  title: {
    fontFamily: "var(--font-display)",
    fontSize: 88,
    fontWeight: 400,
    lineHeight: 1,
    marginBottom: 16,
    letterSpacing: "-0.02em",
  },
  titleAccent: {
    background: "linear-gradient(135deg, var(--text-primary) 30%, var(--accent) 100%)",
    WebkitBackgroundClip: "text",
    WebkitTextFillColor: "transparent",
  },
  subtitle: {
    fontFamily: "var(--font-display)",
    fontStyle: "italic",
    fontSize: 24,
    color: "var(--text-secondary)",
    marginBottom: 20,
  },
  description: {
    fontSize: 16,
    lineHeight: 1.7,
    color: "var(--text-secondary)",
    marginBottom: 40,
    maxWidth: 480,
    marginLeft: "auto",
    marginRight: "auto",
  },
  features: {
    display: "flex",
    flexDirection: "column",
    gap: 12,
    marginBottom: 40,
    textAlign: "left",
  },
  featureCard: {
    display: "flex",
    alignItems: "flex-start",
    gap: 14,
    padding: "14px 18px",
    borderRadius: "var(--radius-md)",
    background: "var(--bg-card)",
    border: "1px solid var(--border)",
  },
  featureIcon: {
    fontSize: 22,
    marginTop: 2,
  },
  featureTitle: {
    fontSize: 14,
    fontWeight: 600,
    color: "var(--text-primary)",
    marginBottom: 3,
  },
  featureDesc: {
    fontSize: 13,
    color: "var(--text-secondary)",
    lineHeight: 1.5,
  },
  startBtn: {
    display: "inline-flex",
    alignItems: "center",
    gap: 10,
    padding: "16px 40px",
    borderRadius: "var(--radius-xl)",
    background: "var(--accent)",
    color: "#0a0c10",
    fontSize: 17,
    fontWeight: 600,
    letterSpacing: "0.01em",
    transition: "all 0.2s ease",
    boxShadow: "0 0 40px var(--accent-glow), 0 4px 20px rgba(0,0,0,0.3)",
    marginBottom: 20,
  },
  startBtnHover: {
    transform: "translateY(-2px)",
    boxShadow: "0 0 60px var(--accent-glow), 0 8px 30px rgba(0,0,0,0.4)",
  },
  arrow: {
    fontSize: 20,
    transition: "transform 0.2s ease",
  },
  hint: {
    fontSize: 13,
    color: "var(--text-muted)",
    lineHeight: 1.5,
  },
};
