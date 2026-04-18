import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import IntroScreen from "./components/IntroScreen.jsx";
import SignInScreen from "./components/SignInScreen.jsx";
import ModeHub from "./components/ModeHub.jsx";
import ItineraryManager from "./components/ItineraryManager.jsx";
import MapView from "./components/MapView.jsx";
import ExploreDock from "./components/ExploreDock.jsx";
import MapSettingsSheet from "./components/MapSettingsSheet.jsx";
import { poiMatchesSelectedInterests } from "./lib/interests.js";
import {
  GROUP_COLOR_PALETTE,
  loadWishlist,
  newWishlistId,
  saveWishlist,
} from "./lib/wishlistStorage.js";

const API = "/api";

const DEFAULT_LAT = 37.3496;
const DEFAULT_LNG = -121.939;
const PASSIVE_KM = 0.35;
const PASSIVE_RING_M = PASSIVE_KM * 1000;
const NEARBY_RADIUS_KM = 2.4;
const MIN_FETCH_INTERVAL_MS = 14_000;
const MIN_MOVE_KM = 0.1;
const PERIODIC_REFRESH_MS = 55_000;
/** Keep POIs on the map across refetches; prune when farther than this from the user. */
const NEARBY_CACHE_PRUNE_KM = 4.8;
const NEARBY_MERGE_CAP = 96;

const SIM_WAYPOINTS = [
  [37.3496, -121.939],
  [37.34855, -121.93733],
  [37.34912, -121.9389],
  [37.3512, -121.9348],
  [37.3544, -121.9552],
];

function toRad(d) {
  return (d * Math.PI) / 180;
}
function toDeg(r) {
  return (r * 180) / Math.PI;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const r = 6371;
  const dlat = toRad(lat2 - lat1);
  const dlng = toRad(lng2 - lng1);
  const a =
    Math.sin(dlat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dlng / 2) ** 2;
  return r * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Upsert fresh Overpass rows into a cache, prune far entries, recompute distances. */
function mergeNearbyRows(cacheMap, freshRows, userLat, userLng) {
  for (const p of freshRows) {
    if (p?.id == null || p.lat == null || p.lng == null) continue;
    cacheMap.set(String(p.id), { ...p });
  }
  for (const [id, p] of [...cacheMap.entries()]) {
    const d = haversineKm(userLat, userLng, p.lat, p.lng);
    if (d > NEARBY_CACHE_PRUNE_KM) cacheMap.delete(id);
  }
  const merged = [...cacheMap.values()].map((p) => ({
    ...p,
    distance_km: Math.round(haversineKm(userLat, userLng, p.lat, p.lng) * 1000) / 1000,
  }));
  merged.sort((a, b) => (a.distance_km || 0) - (b.distance_km || 0));
  return merged.slice(0, NEARBY_MERGE_CAP);
}

function wishItemToPoi(item, group, userLat, userLng) {
  const g = group || { name: "My plans", color: GROUP_COLOR_PALETTE[0] };
  const d = haversineKm(userLat, userLng, item.lat, item.lng);
  return {
    id: `wish-${item.id}`,
    name: item.name,
    lat: item.lat,
    lng: item.lng,
    category: g.name,
    short_description: item.note?.trim()
      ? item.note.trim()
      : `On your ${g.name} list — something you want to do here.`,
    tags: ["wishlist"],
    distance_km: Math.round(d * 1000) / 1000,
  };
}

/** Clockwise from true north, 0–360 */
function bearingDeg(lat1, lng1, lat2, lng2) {
  const y = Math.sin(toRad(lng2 - lng1)) * Math.cos(toRad(lat2));
  const x =
    Math.cos(toRad(lat1)) * Math.sin(toRad(lat2)) -
    Math.sin(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.cos(toRad(lng2 - lng1));
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}

function speakText(text, onStart, onEnd) {
  window.speechSynthesis.cancel();
  const utter = new SpeechSynthesisUtterance(text);
  utter.rate = 0.98;
  utter.pitch = 1;
  utter.onstart = () => onStart?.();
  utter.onend = () => onEnd?.();
  utter.onerror = () => onEnd?.();
  window.speechSynthesis.speak(utter);
}

/** landing → signin → hub → explore | itineraries */
export default function App() {
  const [phase, setPhase] = useState("landing");
  const [userEmail, setUserEmail] = useState(null);
  const inExplore = phase === "explore";
  const [nearby, setNearby] = useState([]);
  const [lat, setLat] = useState(DEFAULT_LAT);
  const [lng, setLng] = useState(DEFAULT_LNG);
  const [headingDeg, setHeadingDeg] = useState(null);
  const [speedMps, setSpeedMps] = useState(null);
  const [interests, setInterests] = useState(["history", "hidden gems"]);
  const [passiveMode, setPassiveMode] = useState(true);
  const [activePoi, setActivePoi] = useState(null);
  const [narration, setNarration] = useState(null);
  const [conversation, setConversation] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [speaking, setSpeaking] = useState(false);
  const [simulating, setSimulating] = useState(false);
  const [poisLoading, setPoisLoading] = useState(false);
  const [lastPoiFetchAt, setLastPoiFetchAt] = useState(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [exploreIdx, setExploreIdx] = useState(0);
  const initialWish = loadWishlist();
  const [wishlistGroups, setWishlistGroups] = useState(initialWish.groups);
  const [wishlistItems, setWishlistItems] = useState(initialWish.items);
  const [wishDropMode, setWishDropMode] = useState(false);
  const [wishDropGroupId, setWishDropGroupId] = useState(
    () => initialWish.groups[0]?.id ?? "g-default"
  );
  /** Itinerary (wishlist group) ids whose pins show on the Explore map. */
  const [visibleWishGroupIds, setVisibleWishGroupIds] = useState(() =>
    initialWish.groups.map((g) => g.id)
  );

  const announcedIds = useRef(new Set());
  const simTimer = useRef(null);
  const simIndex = useRef(0);
  const simPrev = useRef(null);
  const simulatingRef = useRef(false);
  /** When true, map-click / demo position is kept; GPS watch does not overwrite lat/lng. */
  const manualLocationRef = useRef(false);
  const positionHistoryRef = useRef([]);
  const lastFetchRef = useRef({ t: 0, lat: null, lng: null });
  const nearbyRequestIdRef = useRef(0);
  const nearbyCacheRef = useRef(new Map());
  const latRef = useRef(lat);
  const lngRef = useRef(lng);
  const headingRef = useRef(headingDeg);
  const speedRef = useRef(speedMps);

  useEffect(() => {
    latRef.current = lat;
    lngRef.current = lng;
  }, [lat, lng]);
  useEffect(() => {
    headingRef.current = headingDeg;
    speedRef.current = speedMps;
  }, [headingDeg, speedMps]);
  useEffect(() => {
    simulatingRef.current = simulating;
  }, [simulating]);

  useEffect(() => {
    if (!inExplore) {
      nearbyCacheRef.current.clear();
    }
  }, [inExplore]);

  useEffect(() => {
    saveWishlist(wishlistGroups, wishlistItems);
  }, [wishlistGroups, wishlistItems]);

  useEffect(() => {
    const ids = new Set(wishlistGroups.map((g) => g.id));
    setVisibleWishGroupIds((prev) => {
      const kept = prev.filter((id) => ids.has(id));
      const next = [...kept];
      for (const g of wishlistGroups) {
        if (!next.includes(g.id)) next.push(g.id);
      }
      return next;
    });
  }, [wishlistGroups]);

  const wishlistGroupsRef = useRef(wishlistGroups);
  wishlistGroupsRef.current = wishlistGroups;

  const stopAudio = useCallback(() => {
    window.speechSynthesis.cancel();
    setSpeaking(false);
  }, []);

  const playTTS = useCallback(
    (text) => {
      stopAudio();
      speakText(text, () => setSpeaking(true), () => setSpeaking(false));
    },
    [stopAudio]
  );

  const fetchNearby = useCallback(
    async (force = false) => {
      const la = latRef.current;
      const lo = lngRef.current;
      const last = lastFetchRef.current;
      if (last.lat != null && last.lng != null && !force) {
        const moved = haversineKm(last.lat, last.lng, la, lo);
        const age = Date.now() - last.t;
        if (age < MIN_FETCH_INTERVAL_MS && moved < MIN_MOVE_KM) {
          return;
        }
      }

      const requestId = ++nearbyRequestIdRef.current;
      setPoisLoading(true);
      setError(null);
      try {
        const res = await fetch(`${API}/nearby`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            lat: la,
            lng: lo,
            radius_km: NEARBY_RADIUS_KM,
            heading_deg: headingRef.current,
            speed_mps: speedRef.current,
          }),
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.detail || `Nearby failed (${res.status})`);
        }
        const data = await res.json();
        if (requestId !== nearbyRequestIdRef.current) {
          return;
        }
        const fresh = Array.isArray(data) ? data : [];
        const merged = mergeNearbyRows(nearbyCacheRef.current, fresh, la, lo);
        setNearby(merged);
        lastFetchRef.current = { t: Date.now(), lat: la, lng: lo };
        setLastPoiFetchAt(Date.now());
      } catch (e) {
        console.error(e);
        if (requestId !== nearbyRequestIdRef.current) {
          return;
        }
        setError(e.message || "Could not load nearby places");
        // Keep last successful markers — do not clear on transient Overpass/network errors.
      } finally {
        if (requestId === nearbyRequestIdRef.current) {
          setPoisLoading(false);
        }
      }
    },
    []
  );

  // Only refetch when the map anchor moves — not on every heading/speed tweak (avoids
  // hammering Overpass and empty bbox edge cases).
  useEffect(() => {
    if (!inExplore) return;
    const t = setTimeout(() => fetchNearby(false), 0);
    return () => clearTimeout(t);
  }, [lat, lng, inExplore, fetchNearby]);

  useEffect(() => {
    if (!inExplore) return;
    const id = setInterval(() => fetchNearby(true), PERIODIC_REFRESH_MS);
    return () => clearInterval(id);
  }, [inExplore, fetchNearby]);

  useEffect(() => {
    if (!inExplore || !navigator.geolocation) return;
    const wid = navigator.geolocation.watchPosition(
      (pos) => {
        if (simulatingRef.current) return;
        if (manualLocationRef.current) return;
        const t = Date.now();
        const la = pos.coords.latitude;
        const lo = pos.coords.longitude;
        const hist = positionHistoryRef.current;
        hist.push({ t, lat: la, lng: lo });
        while (hist.length > 12) hist.shift();
        if (hist.length >= 2) {
          const b = hist[hist.length - 1];
          const a = hist[hist.length - 2];
          const dt = (b.t - a.t) / 1000;
          const distKm = haversineKm(a.lat, a.lng, b.lat, b.lng);
          if (dt > 0.25 && distKm > 0.012) {
            setSpeedMps((distKm * 1000) / dt);
            setHeadingDeg(bearingDeg(a.lat, a.lng, b.lat, b.lng));
          }
        }
        setLat(la);
        setLng(lo);
      },
      () => {},
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 25000 }
    );
    return () => navigator.geolocation.clearWatch(wid);
  }, [inExplore]);

  const narratePoi = useCallback(
    async (poi) => {
      const poiId = poi.id;
      setLoading(true);
      setError(null);
      try {
        const res = await fetch(`${API}/narrate`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            poi_id: poiId,
            interests,
            name: poi.name,
            category: poi.category,
            short_description: poi.short_description,
            tags: poi.tags,
          }),
        });
        if (!res.ok) {
          const err = await res.json().catch(() => ({}));
          throw new Error(err.detail || `Narration failed (${res.status})`);
        }
        const data = await res.json();
        setActivePoi(poi);
        setNarration(data.narration);
        setConversation([{ role: "assistant", content: data.narration }]);
        setLoading(false);
        playTTS(data.narration);
      } catch (e) {
        console.error(e);
        announcedIds.current.delete(poiId);
        setError(e.message || "Could not load narration");
        setLoading(false);
      }
    },
    [interests, playTTS]
  );

  const matchedPois = useMemo(
    () => nearby.filter((p) => poiMatchesSelectedInterests(p, interests)),
    [nearby, interests]
  );

  const insideRingPois = useMemo(
    () =>
      [...matchedPois]
        .filter((p) => p.distance_km < PASSIVE_KM)
        .sort((a, b) => a.distance_km - b.distance_km),
    [matchedPois]
  );

  const outsideRingPois = useMemo(
    () =>
      [...matchedPois]
        .filter((p) => p.distance_km >= PASSIVE_KM)
        .sort((a, b) => a.distance_km - b.distance_km),
    [matchedPois]
  );

  const groupsById = useMemo(
    () => new Map(wishlistGroups.map((g) => [g.id, g])),
    [wishlistGroups]
  );

  const visibleWishGroupSet = useMemo(
    () => new Set(visibleWishGroupIds),
    [visibleWishGroupIds]
  );

  const ringExplorePois = useMemo(() => {
    const osm = insideRingPois.map((p) => ({ ...p, isWishlist: false }));
    const wl = wishlistItems
      .filter((w) => visibleWishGroupSet.has(w.groupId))
      .filter((w) => haversineKm(lat, lng, w.lat, w.lng) < PASSIVE_KM)
      .map((w) => {
        const g = groupsById.get(w.groupId) || wishlistGroups[0];
        return {
          ...wishItemToPoi(w, g, lat, lng),
          isWishlist: true,
        };
      });
    return [...osm, ...wl].sort((a, b) => a.distance_km - b.distance_km);
  }, [insideRingPois, wishlistItems, groupsById, wishlistGroups, lat, lng, visibleWishGroupSet]);

  const wishlistMarkers = useMemo(
    () =>
      wishlistItems
        .filter((item) => visibleWishGroupSet.has(item.groupId))
        .map((item) => {
          const g = groupsById.get(item.groupId) || wishlistGroups[0];
          return {
            groupColor: g.color,
            groupName: g.name,
            poi: wishItemToPoi(item, g, lat, lng),
          };
        }),
    [wishlistItems, groupsById, wishlistGroups, lat, lng, visibleWishGroupSet]
  );

  useEffect(() => {
    if (ringExplorePois.length === 0) {
      setExploreIdx(0);
      return;
    }
    setExploreIdx((i) => (i >= ringExplorePois.length ? 0 : i));
  }, [ringExplorePois]);

  useEffect(() => {
    if (!activePoi || ringExplorePois.length === 0) return;
    const i = ringExplorePois.findIndex((p) => p.id === activePoi.id);
    if (i >= 0) setExploreIdx(i);
  }, [activePoi, ringExplorePois]);

  const handleNext = useCallback(() => {
    if (ringExplorePois.length === 0) return;
    const ni = (exploreIdx + 1) % ringExplorePois.length;
    setExploreIdx(ni);
    narratePoi(ringExplorePois[ni]);
  }, [ringExplorePois, exploreIdx, narratePoi]);

  useEffect(() => {
    if (!passiveMode || loading) return;
    const close = ringExplorePois.length ? ringExplorePois[0] : null;
    if (!close) return;
    if (announcedIds.current.has(close.id)) return;
    announcedIds.current.add(close.id);
    narratePoi(close);
  }, [ringExplorePois, passiveMode, loading, narratePoi]);

  const toggleInterest = (key) => {
    setInterests((prev) =>
      prev.includes(key) ? prev.filter((x) => x !== key) : [...prev, key]
    );
  };

  const handleSelectPoi = useCallback(
    (poi) => {
      narratePoi(poi);
    },
    [narratePoi]
  );

  const handleSend = async (message) => {
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
          name: activePoi.name,
          category: activePoi.category,
          tags: activePoi.tags,
        }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || `Chat failed (${res.status})`);
      }
      const data = await res.json();
      setConversation((prev) => [
        ...prev,
        { role: "assistant", content: data.reply },
      ]);
      setNarration(data.reply);
      setLoading(false);
      playTTS(data.reply);
    } catch (e) {
      console.error(e);
      setError(e.message || "Chat request failed");
      setLoading(false);
    }
  };

  const handleDismiss = () => {
    stopAudio();
    setActivePoi(null);
    setNarration(null);
    setConversation([]);
    setError(null);
  };

  const handleGeolocate = () => {
    if (!navigator.geolocation) {
      setError("Geolocation is not available in this browser.");
      return;
    }
    manualLocationRef.current = false;
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(pos.coords.latitude);
        setLng(pos.coords.longitude);
        setError(null);
        fetchNearby(true);
      },
      () => setError("Location permission denied or unavailable."),
      { enableHighAccuracy: true, maximumAge: 5000, timeout: 20_000 }
    );
  };

  const clearSimulation = useCallback(() => {
    if (simTimer.current) {
      clearInterval(simTimer.current);
      simTimer.current = null;
    }
    simPrev.current = null;
    setSimulating(false);
  }, []);

  const toggleSimulation = () => {
    if (simulating) {
      clearSimulation();
      return;
    }
    setSimulating(true);
    manualLocationRef.current = false;
    simIndex.current = 0;
    simPrev.current = null;
    const tick = () => {
      const [la, lo] = SIM_WAYPOINTS[simIndex.current % SIM_WAYPOINTS.length];
      if (simPrev.current) {
        const [pla, plo] = simPrev.current;
        const distKm = haversineKm(pla, plo, la, lo);
        const dt = 4.5;
        setSpeedMps((distKm * 1000) / dt);
        setHeadingDeg(bearingDeg(pla, plo, la, lo));
      }
      simPrev.current = [la, lo];
      simIndex.current += 1;
      setLat(la);
      setLng(lo);
    };
    tick();
    simTimer.current = setInterval(tick, 4500);
  };

  useEffect(() => () => clearSimulation(), [clearSimulation]);

  const startWishDrop = useCallback((groupId) => {
    setWishDropGroupId(groupId);
    setWishDropMode(true);
    setSettingsOpen(false);
  }, []);

  const cancelWishDrop = useCallback(() => setWishDropMode(false), []);

  const toggleWishGroupMapVisible = useCallback((groupId) => {
    setVisibleWishGroupIds((prev) =>
      prev.includes(groupId) ? prev.filter((id) => id !== groupId) : [...prev, groupId]
    );
  }, []);

  const setAllWishGroupsMapVisible = useCallback((show) => {
    if (show) {
      setVisibleWishGroupIds(wishlistGroupsRef.current.map((g) => g.id));
    } else {
      setVisibleWishGroupIds([]);
    }
  }, []);

  const addWishlistItem = useCallback((partial) => {
    const gid = partial.groupId || wishlistGroups[0]?.id;
    setWishlistItems((prev) => [
      ...prev,
      {
        id: newWishlistId(),
        name: partial.name,
        lat: partial.lat,
        lng: partial.lng,
        note: partial.note || "",
        groupId: gid,
      },
    ]);
  }, [wishlistGroups]);

  const handleMapPick = useCallback(
    (la, lo) => {
      if (wishDropMode) {
        const name = window.prompt("Name this plan:");
        if (name?.trim()) {
          const note = window.prompt("Optional note (cancel to skip):") ?? "";
          addWishlistItem({
            name: name.trim(),
            note: typeof note === "string" ? note.trim() : "",
            lat: la,
            lng: lo,
            groupId: wishDropGroupId,
          });
        }
        setWishDropMode(false);
        return;
      }
      clearSimulation();
      manualLocationRef.current = true;
      setHeadingDeg(null);
      setSpeedMps(null);
      setLat(la);
      setLng(lo);
    },
    [wishDropMode, wishDropGroupId, addWishlistItem, clearSimulation]
  );

  const removeWishlistItem = useCallback((id) => {
    setWishlistItems((prev) => prev.filter((x) => x.id !== id));
  }, []);

  const updateWishlistItem = useCallback((id, patch) => {
    setWishlistItems((prev) =>
      prev.map((x) => (x.id === id ? { ...x, ...patch } : x))
    );
  }, []);

  const addWishlistGroup = useCallback((name, onCreated) => {
    const id = `g-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
    setWishlistGroups((g) => {
      const color = GROUP_COLOR_PALETTE[g.length % GROUP_COLOR_PALETTE.length];
      return [...g, { id, name, color }];
    });
    onCreated?.(id);
  }, []);

  const removeWishlistGroup = useCallback((groupId) => {
    const groups = wishlistGroupsRef.current;
    if (groups.length <= 1) return;
    const replacement = groups.find((x) => x.id !== groupId);
    if (!replacement) return;
    setWishlistItems((items) =>
      items.map((it) =>
        it.groupId === groupId ? { ...it, groupId: replacement.id } : it
      )
    );
    setWishlistGroups((g) => g.filter((x) => x.id !== groupId));
    setWishDropGroupId((cur) => (cur === groupId ? replacement.id : cur));
  }, []);

  const motionHint =
    headingDeg != null && speedMps != null && speedMps > 0.4
      ? `Heading ~${Math.round(headingDeg)}°, ~${speedMps.toFixed(1)} m/s — search biased forward.`
      : "Move a bit to estimate direction; Orbit biases POI search along your bearing when speed picks up.";

  const nextDisabled = ringExplorePois.length <= 1;
  const nextLabel =
    ringExplorePois.length > 0
      ? `Next (${(exploreIdx % ringExplorePois.length) + 1}/${ringExplorePois.length})`
      : "Next";

  if (phase === "landing") {
    return <IntroScreen onSignIn={() => setPhase("signin")} />;
  }
  if (phase === "signin") {
    return (
      <SignInScreen
        onBack={() => setPhase("landing")}
        onSignedIn={(email) => {
          setUserEmail(email);
          setPhase("hub");
        }}
      />
    );
  }
  if (phase === "hub") {
    return (
      <ModeHub
        displayName={userEmail || "Traveler"}
        onExplore={() => setPhase("explore")}
        onManageItineraries={() => setPhase("itineraries")}
        onSignOut={() => {
          setUserEmail(null);
          setPhase("landing");
        }}
      />
    );
  }
  if (phase === "itineraries") {
    return (
      <ItineraryManager
        biasLat={lat}
        biasLng={lng}
        wishlistGroups={wishlistGroups}
        wishlistItems={wishlistItems}
        onAddWishlistGroup={addWishlistGroup}
        onRemoveWishlistGroup={removeWishlistGroup}
        onAddWishlistItem={addWishlistItem}
        onRemoveWishlistItem={removeWishlistItem}
        onBack={() => setPhase("hub")}
        onOpenExplore={() => setPhase("explore")}
      />
    );
  }

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100%",
        width: "100%",
        overflow: "hidden",
      }}
    >
      <div style={{ flex: 1, position: "relative", minHeight: 0, minWidth: 0 }}>
        <MapView
          userLat={lat}
          userLng={lng}
          insideOsmPois={insideRingPois}
          outsideOsmPois={outsideRingPois}
          wishlistMarkers={wishlistMarkers}
          passiveMode={passiveMode}
          passiveRadiusM={PASSIVE_RING_M}
          onPickLocation={handleMapPick}
          onSelectPoi={handleSelectPoi}
          simulating={simulating}
        />
        {wishDropMode && (
          <div
            style={{
              position: "absolute",
              left: 14,
              right: 14,
              top: 52,
              zIndex: 701,
              padding: "10px 14px",
              borderRadius: 10,
              fontSize: 12,
              color: "#fef3c7",
              background: "rgba(88, 28, 135, 0.92)",
              border: "1px solid rgba(233, 213, 255, 0.35)",
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 10,
            }}
          >
            <span>Tap the map to drop a plan pin.</span>
            <button
              type="button"
              onClick={cancelWishDrop}
              style={{
                border: "1px solid rgba(255,255,255,0.25)",
                borderRadius: 8,
                padding: "6px 12px",
                background: "transparent",
                color: "#fef3c7",
                cursor: "pointer",
                fontSize: 12,
              }}
            >
              Cancel
            </button>
          </div>
        )}
        <button
          type="button"
          onClick={() => setPhase("hub")}
          style={{
            position: "absolute",
            top: 14,
            left: 14,
            zIndex: 700,
            border: "1px solid var(--border)",
            borderRadius: 10,
            padding: "8px 14px",
            fontSize: 13,
            fontWeight: 600,
            background: "rgba(11,16,32,0.92)",
            color: "var(--text)",
            cursor: "pointer",
            boxShadow: "0 4px 16px rgba(0,0,0,0.25)",
          }}
        >
          Menu
        </button>
        <button
          type="button"
          onClick={() => setSettingsOpen(true)}
          style={{
            position: "absolute",
            top: 14,
            right: 14,
            zIndex: 700,
            border: "1px solid var(--border)",
            borderRadius: 10,
            padding: "8px 14px",
            fontSize: 13,
            fontWeight: 600,
            background: "rgba(11,16,32,0.92)",
            color: "var(--text)",
            cursor: "pointer",
            boxShadow: "0 4px 16px rgba(0,0,0,0.25)",
          }}
        >
          Filters
        </button>
        <div
          style={{
            position: "absolute",
            left: 14,
            top: 56,
            zIndex: 700,
            padding: "10px 14px",
            borderRadius: 10,
            fontSize: 11,
            color: "var(--text)",
            background: "rgba(11,16,32,0.9)",
            border: "1px solid var(--border)",
            maxWidth: 280,
            lineHeight: 1.45,
          }}
        >
          <div>
            OSM pins follow <strong>Filters</strong>. Star pins respect itinerary “on map” toggles.{" "}
            <strong>Now exploring</strong> uses the ring only (~{Math.round(PASSIVE_RING_M)} m).
          </div>
          <div style={{ marginTop: 6, color: "var(--muted)" }}>{motionHint}</div>
          <div style={{ marginTop: 6, color: "var(--muted)" }}>
            Map click locks position until <strong style={{ color: "var(--text)" }}>GPS</strong>{" "}
            in Filters.
          </div>
        </div>
        <MapSettingsSheet
          open={settingsOpen}
          onClose={() => setSettingsOpen(false)}
          interests={interests}
          onToggleInterest={toggleInterest}
          passiveMode={passiveMode}
          onTogglePassive={setPassiveMode}
          onGeolocate={handleGeolocate}
          onSimulate={toggleSimulation}
          simulating={simulating}
          insideRingPois={insideRingPois}
          outsideRingPois={outsideRingPois}
          ringRadiusM={PASSIVE_RING_M}
          lastPoiFetchAt={lastPoiFetchAt}
          onSelectPoi={handleSelectPoi}
          noInterests={interests.length === 0}
          wishlistGroups={wishlistGroups}
          wishlistItems={wishlistItems}
          userLat={lat}
          userLng={lng}
          passiveKm={PASSIVE_KM}
          onStartWishDrop={startWishDrop}
          onAddWishlistGroup={addWishlistGroup}
          onRemoveWishlistGroup={removeWishlistGroup}
          onRemoveWishlistItem={removeWishlistItem}
          onUpdateWishlistItem={updateWishlistItem}
          visibleWishGroupIds={visibleWishGroupIds}
          onToggleWishGroupMapVisible={toggleWishGroupMapVisible}
          onSetAllWishGroupsMapVisible={setAllWishGroupsMapVisible}
        />
      </div>
      <ExploreDock
        activePoi={activePoi}
        narration={narration}
        conversation={conversation}
        loading={loading || poisLoading}
        error={error}
        speaking={speaking}
        onNext={handleNext}
        nextDisabled={nextDisabled}
        nextLabel={nextLabel}
        onReplay={() => narration && playTTS(narration)}
        onStop={stopAudio}
        onDismiss={handleDismiss}
        onSend={handleSend}
      />
    </div>
  );
}
