import { useState, useRef, useCallback } from "react";
import IntroScreen from "./components/IntroScreen";
import MapPanel from "./components/MapPanel";
import PhoneMockup from "./components/PhoneMockup";

const API = "/api";

export default function App() {
  const [started, setStarted] = useState(false);
  const [nearbyPois, setNearbyPois] = useState([]);
  const [activePoi, setActivePoi] = useState(null);
  const [narration, setNarration] = useState(null);
  const [conversation, setConversation] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [interests] = useState([
    "climbing",
    "outdoors",
    "food",
    "history",
    "hidden gems",
  ]);
  const [highlightPoi, setHighlightPoi] = useState(null);
  const [speaking, setSpeaking] = useState(false);

  const announcedIds = useRef(new Set());
  const audioRef = useRef(null);

  const stopAudio = () => {
    if (audioRef.current) {
      audioRef.current.pause();
      audioRef.current.onended = null;
      audioRef.current.onerror = null;
    }
    window.speechSynthesis.cancel();
    setSpeaking(false);
  };

  const playTTS = async (text) => {
    stopAudio();
    setSpeaking(true);

    try {
      const res = await fetch(`${API}/tts`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });

      if (!res.ok) throw new Error("TTS request failed");

      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audioRef.current = audio;

      audio.onended = () => {
        setSpeaking(false);
        URL.revokeObjectURL(url);
      };
      audio.onerror = () => {
        setSpeaking(false);
        URL.revokeObjectURL(url);
        fallbackSpeak(text);
      };

      await audio.play();
    } catch {
      fallbackSpeak(text);
    }
  };

  const fallbackSpeak = (text) => {
    window.speechSynthesis.cancel();
    const utter = new SpeechSynthesisUtterance(text);
    utter.rate = 0.95;
    utter.pitch = 1.05;
    const voices = window.speechSynthesis.getVoices();
    const preferred = voices.find(
      (v) =>
        v.name.includes("Samantha (Enhanced)") ||
        v.name.includes("Zoe (Enhanced)") ||
        v.name.includes("Karen (Enhanced)") ||
        v.name.includes("Samantha")
    );
    if (preferred) utter.voice = preferred;
    utter.onstart = () => setSpeaking(true);
    utter.onend = () => setSpeaking(false);
    utter.onerror = () => setSpeaking(false);
    window.speechSynthesis.speak(utter);
  };

  const narratePoi = useCallback(
    async (poiId) => {
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(`${API}/narrate`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ poi_id: poiId, interests }),
        });
        if (!res.ok) {
          const errData = await res.json().catch(() => ({}));
          throw new Error(errData.detail || `Narration failed (${res.status})`);
        }
        const data = await res.json();
        setActivePoi({ id: data.poi_id, name: data.name });
        setNarration(data.narration);
        setConversation([{ role: "assistant", content: data.narration }]);
        setLoading(false);

        await playTTS(data.narration);
      } catch (err) {
        console.error("Narration error:", err);
        setError(err.message);
        setLoading(false);
      }
    },
    [interests]
  );

  const fetchNearby = useCallback(
    async (lat, lng) => {
      try {
        const res = await fetch(`${API}/nearby`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ lat, lng, radius_km: 30 }),
        });
        if (!res.ok) return;
        const pois = await res.json();
        setNearbyPois(pois);

        const closest = pois.find((p) => !announcedIds.current.has(p.id));
        if (closest && closest.distance_km < 20) {
          announcedIds.current.add(closest.id);
          narratePoi(closest.id);
        }
      } catch (err) {
        console.error("Failed to fetch nearby POIs:", err);
      }
    },
    [narratePoi]
  );

  const converse = async (message) => {
    if (!activePoi) return;
    setConversation((prev) => [...prev, { role: "user", content: message }]);
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`${API}/converse`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          poi_id: activePoi.id,
          message,
          interests,
        }),
      });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        throw new Error(errData.detail || `Request failed (${res.status})`);
      }
      const data = await res.json();
      setConversation((prev) => [
        ...prev,
        { role: "assistant", content: data.reply },
      ]);
      setNarration(data.reply);
      setLoading(false);

      await playTTS(data.reply);
    } catch (err) {
      console.error("Conversation error:", err);
      setError(err.message);
      setLoading(false);
    }
  };

  const handleTellMore = () => {
    converse(
      "Tell me more about this place — what's the most interesting thing about it?"
    );
  };

  const handleDirections = () => {
    if (activePoi) {
      const poi = nearbyPois.find((p) => p.id === activePoi.id);
      if (poi) setHighlightPoi(poi);
    }
    converse("How do I get there? Any tips for visiting?");
  };

  const handleDismiss = () => {
    stopAudio();
    setActivePoi(null);
    setNarration(null);
    setConversation([]);
    setHighlightPoi(null);
    setError(null);
  };

  const handleReplay = () => {
    if (narration) playTTS(narration);
  };

  const resetDemo = async () => {
    stopAudio();
    announcedIds.current = new Set();
    setActivePoi(null);
    setNarration(null);
    setConversation([]);
    setNearbyPois([]);
    setHighlightPoi(null);
    setError(null);
    try {
      await fetch(`${API}/conversation`, { method: "DELETE" });
    } catch {}
  };

  if (!started) {
    return <IntroScreen onStart={() => setStarted(true)} />;
  }

  return (
    <div
      style={{
        display: "flex",
        height: "100vh",
        width: "100vw",
        background: "var(--bg-deep)",
      }}
    >
      <div style={{ flex: 1, position: "relative" }}>
        <MapPanel
          onLocationChange={fetchNearby}
          nearbyPois={nearbyPois}
          highlightPoi={highlightPoi}
          onResetDemo={resetDemo}
        />
      </div>
      <div
        style={{
          width: 420,
          minWidth: 420,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          padding: "24px 24px 24px 0",
        }}
      >
        <PhoneMockup
          activePoi={activePoi}
          narration={narration}
          conversation={conversation}
          loading={loading}
          error={error}
          interests={interests}
          speaking={speaking}
          onTellMore={handleTellMore}
          onDirections={handleDirections}
          onDismiss={handleDismiss}
          onConverse={converse}
          onReplay={handleReplay}
          onStopAudio={stopAudio}
        />
      </div>
    </div>
  );
}
