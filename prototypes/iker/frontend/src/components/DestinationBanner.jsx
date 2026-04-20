import { useCallback, useEffect, useRef, useState } from "react";

// Use the browser's built-in Web Speech API to give the narration an "Orbit-as-voice"
// feel at the gallery walk. We don't depend on Groq TTS because the browser version
// is free, zero-latency, and doesn't need an API key for a first demo.
function useSpeech() {
  const [supported, setSupported] = useState(false);
  const [speaking, setSpeaking] = useState(false);
  const utteranceRef = useRef(null);

  useEffect(() => {
    if (typeof window !== "undefined" && "speechSynthesis" in window) {
      setSupported(true);
    }
    return () => {
      if (typeof window !== "undefined" && "speechSynthesis" in window) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const speak = useCallback((text) => {
    if (!supported || !text) return;
    window.speechSynthesis.cancel();
    const u = new SpeechSynthesisUtterance(text);
    u.rate = 0.98;
    u.pitch = 1.02;
    u.onstart = () => setSpeaking(true);
    u.onend = () => setSpeaking(false);
    u.onerror = () => setSpeaking(false);
    utteranceRef.current = u;
    window.speechSynthesis.speak(u);
  }, [supported]);

  const stop = useCallback(() => {
    if (!supported) return;
    window.speechSynthesis.cancel();
    setSpeaking(false);
  }, [supported]);

  return { supported, speaking, speak, stop };
}

export default function DestinationBanner({ state, actions }) {
  const { destination, narration } = state;
  const { supported, speaking, speak, stop } = useSpeech();

  useEffect(() => {
    if (!destination || !narration) return;
    const t = setTimeout(() => speak(narration), 150);
    return () => clearTimeout(t);
  }, [destination?.id, narration, speak]);

  if (!destination) return null;

  return (
    <div className="destination">
      <div className="mark" role="img" aria-label="go">
        🧭
      </div>
      <div style={{ flex: 1 }}>
        <div className="title">Next stop · {destination.walk_minutes} min walk</div>
        <h3>{destination.name}</h3>
        <p className="narration">{narration || destination.blurb}</p>
        <div className="speak row" style={{ flexWrap: "wrap", gap: "0.4rem" }}>
          {supported && (
            <button
              onClick={() => (speaking ? stop() : speak(narration || destination.blurb))}
            >
              {speaking ? "⏹ stop" : "▶︎ replay narration"}
            </button>
          )}
          <button className="ghost" onClick={() => actions.softReset()}>
            Clear & get new picks
          </button>
        </div>
      </div>
    </div>
  );
}
