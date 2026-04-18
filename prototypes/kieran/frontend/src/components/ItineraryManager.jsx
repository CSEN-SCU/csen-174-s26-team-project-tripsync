import { useCallback, useEffect, useMemo, useState } from "react";

const API = "/api";

function toRad(d) {
  return (d * Math.PI) / 180;
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

function formatApiDetail(detail) {
  if (detail == null) return null;
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail
      .map((x) => (typeof x === "object" && x?.msg ? String(x.msg) : JSON.stringify(x)))
      .join("; ");
  }
  if (typeof detail === "object") return JSON.stringify(detail);
  return String(detail);
}

const btnSecondary = {
  borderRadius: 8,
  padding: "8px 12px",
  fontSize: 12,
  border: "1px solid var(--border)",
  background: "transparent",
  color: "var(--text)",
  cursor: "pointer",
};

export default function ItineraryManager({
  biasLat,
  biasLng,
  wishlistGroups,
  wishlistItems,
  onAddWishlistGroup,
  onRemoveWishlistGroup,
  onAddWishlistItem,
  onRemoveWishlistItem,
  onBack,
  onOpenExplore,
}) {
  const [selectedId, setSelectedId] = useState(null);
  const [newGroupName, setNewGroupName] = useState("");
  const [searchQ, setSearchQ] = useState("");
  const [searching, setSearching] = useState(false);
  const [searchErr, setSearchErr] = useState(null);
  const [results, setResults] = useState([]);
  const [picked, setPicked] = useState(null);
  const [note, setNote] = useState("");

  const groupsById = useMemo(
    () => new Map(wishlistGroups.map((g) => [g.id, g])),
    [wishlistGroups]
  );

  const selected = selectedId ? groupsById.get(selectedId) : null;

  useEffect(() => {
    if (selectedId && !groupsById.has(selectedId)) {
      setSelectedId(null);
    }
  }, [selectedId, groupsById]);

  const stopsForSelected = useMemo(() => {
    if (!selectedId) return [];
    return wishlistItems
      .filter((it) => it.groupId === selectedId)
      .map((it) => ({
        ...it,
        distance_km:
          Math.round(haversineKm(biasLat, biasLng, it.lat, it.lng) * 1000) / 1000,
      }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [wishlistItems, selectedId, biasLat, biasLng]);

  const runSearch = useCallback(async () => {
    const q = searchQ.trim();
    if (q.length < 2) {
      setSearchErr("Type at least 2 characters.");
      setResults([]);
      return;
    }
    setSearching(true);
    setSearchErr(null);
    setPicked(null);
    try {
      const res = await fetch(`${API}/geocode`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ q, lat: biasLat, lng: biasLng }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        const msg = formatApiDetail(err.detail) || `Search failed (${res.status})`;
        throw new Error(msg);
      }
      const data = await res.json();
      setResults(Array.isArray(data) ? data : []);
      if (!Array.isArray(data) || !data.length) {
        setSearchErr("No matches — try a different phrase.");
      }
    } catch (e) {
      const msg = e?.message || "Search failed";
      setSearchErr(
        msg === "Failed to fetch"
          ? "Could not reach the server. Start the backend (port 8001) and use the Vite dev app so /api is proxied."
          : msg
      );
      setResults([]);
    } finally {
      setSearching(false);
    }
  }, [searchQ, biasLat, biasLng]);

  const addStop = (e) => {
    e.preventDefault();
    if (!selectedId || !picked) return;
    onAddWishlistItem({
      name: picked.label.split(",").slice(0, 2).join(",").trim() || picked.label,
      note: note.trim(),
      lat: picked.lat,
      lng: picked.lng,
      groupId: selectedId,
    });
    setNote("");
    setPicked(null);
    setSearchQ("");
    setResults([]);
  };

  const createItinerary = (e) => {
    e.preventDefault();
    const n = newGroupName.trim();
    if (!n) return;
    onAddWishlistGroup(n, (id) => {
      setSelectedId(id);
      setNewGroupName("");
    });
  };

  if (selected && selectedId) {
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
          <button type="button" onClick={() => setSelectedId(null)} style={{ ...btnSecondary, flexShrink: 0 }}>
            ← Itineraries
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
              Editing
            </div>
            <div style={{ fontWeight: 700, fontSize: 17, display: "flex", alignItems: "center", gap: 8 }}>
              <span
                style={{
                  width: 10,
                  height: 10,
                  borderRadius: "50%",
                  background: selected.color,
                  flexShrink: 0,
                }}
              />
              <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {selected.name}
              </span>
            </div>
          </div>
          <button type="button" onClick={onOpenExplore} style={{ ...btnSecondary, flexShrink: 0 }}>
            Explore map
          </button>
        </header>

        <div style={{ flex: 1, overflow: "auto", padding: "16px 16px 28px", maxWidth: 560, margin: "0 auto", width: "100%" }}>
          <p style={{ margin: "0 0 14px", fontSize: 13, color: "var(--muted)", lineHeight: 1.55 }}>
            Search like in Maps, pick a result, then add it to <strong style={{ color: "var(--text)" }}>this</strong>{" "}
            itinerary only. Optional note is for your own reminder.
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
            <h2 style={{ margin: "0 0 10px", fontSize: 15, fontWeight: 700 }}>Add a stop (search)</h2>
            <form
              onSubmit={(ev) => {
                ev.preventDefault();
                runSearch();
              }}
              style={{ display: "flex", gap: 8, flexWrap: "wrap" }}
            >
              <input
                value={searchQ}
                onChange={(ev) => setSearchQ(ev.target.value)}
                placeholder="Search places, addresses…"
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
                disabled={searching}
                style={{
                  border: "none",
                  borderRadius: 10,
                  padding: "10px 16px",
                  fontWeight: 600,
                  background: "linear-gradient(135deg, var(--accent), #e09a1f)",
                  color: "#1a1204",
                  opacity: searching ? 0.7 : 1,
                }}
              >
                {searching ? "Searching…" : "Search"}
              </button>
            </form>
            {searchErr && (
              <div style={{ marginTop: 10, fontSize: 12, color: "var(--danger)" }}>{searchErr}</div>
            )}
            {results.length > 0 && (
              <ul style={{ listStyle: "none", margin: "12px 0 0", padding: 0, maxHeight: 220, overflow: "auto" }}>
                {results.map((r, i) => {
                  const on = picked?.lat === r.lat && picked?.lng === r.lng && picked?.label === r.label;
                  return (
                    <li key={`${r.lat},${r.lng},${i}`}>
                      <button
                        type="button"
                        onClick={() => {
                          setPicked(r);
                          setSearchErr(null);
                        }}
                        style={{
                          width: "100%",
                          textAlign: "left",
                          padding: "10px 10px",
                          marginBottom: 6,
                          borderRadius: 10,
                          border: on ? "2px solid var(--accent)" : "1px solid var(--border)",
                          background: on ? "rgba(244,185,66,0.12)" : "rgba(0,0,0,0.15)",
                          color: "var(--text)",
                          fontSize: 13,
                          lineHeight: 1.4,
                          cursor: "pointer",
                        }}
                      >
                        {r.label}
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
            <form onSubmit={addStop} style={{ marginTop: 14 }}>
              <label style={{ display: "block", fontSize: 12, color: "var(--muted)", marginBottom: 6 }}>
                Note (optional)
                <input
                  value={note}
                  onChange={(ev) => setNote(ev.target.value)}
                  placeholder="e.g. meet at 2pm"
                  style={{
                    display: "block",
                    width: "100%",
                    marginTop: 6,
                    padding: "10px 12px",
                    borderRadius: 10,
                    border: "1px solid var(--border)",
                    background: "rgba(0,0,0,0.2)",
                    color: "var(--text)",
                  }}
                />
              </label>
              <button
                type="submit"
                disabled={!picked}
                style={{
                  width: "100%",
                  marginTop: 12,
                  border: "none",
                  borderRadius: 10,
                  padding: "12px 14px",
                  fontWeight: 600,
                  background: picked ? "linear-gradient(135deg, #38bdf8, #0ea5e9)" : "rgba(255,255,255,0.1)",
                  color: picked ? "#0b1020" : "var(--muted)",
                }}
              >
                Add selected place to this itinerary
              </button>
            </form>
          </section>

          <section
            style={{
              padding: 16,
              borderRadius: "var(--radius)",
              border: "1px solid var(--border)",
              background: "var(--panel)",
            }}
          >
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
              <h2 style={{ margin: 0, fontSize: 15, fontWeight: 700 }}>Stops in this itinerary</h2>
              {wishlistGroups.length > 1 && (
                <button
                  type="button"
                  onClick={() => {
                    if (
                      window.confirm(
                        `Remove itinerary “${selected.name}” and reassign its stops?`
                      )
                    ) {
                      onRemoveWishlistGroup(selectedId);
                      setSelectedId(null);
                    }
                  }}
                  style={{
                    ...btnSecondary,
                    fontSize: 11,
                    color: "var(--danger)",
                    borderColor: "rgba(248,113,113,0.35)",
                  }}
                >
                  Delete itinerary
                </button>
              )}
            </div>
            <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
              {stopsForSelected.map((row) => (
                <li
                  key={row.id}
                  style={{
                    padding: "12px 0",
                    borderBottom: "1px solid rgba(255,255,255,0.06)",
                    fontSize: 13,
                  }}
                >
                  <div style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
                    <span style={{ fontSize: 15, color: selected.color, flexShrink: 0 }}>★</span>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontWeight: 700 }}>{row.name}</div>
                      <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 4 }}>
                        ~{row.distance_km} km from map anchor · {row.lat.toFixed(4)}, {row.lng.toFixed(4)}
                      </div>
                      {row.note?.trim() && (
                        <div style={{ fontSize: 12, color: "var(--muted)", marginTop: 6 }}>{row.note}</div>
                      )}
                    </div>
                    <button
                      type="button"
                      onClick={() => onRemoveWishlistItem(row.id)}
                      style={{
                        ...btnSecondary,
                        fontSize: 11,
                        flexShrink: 0,
                        color: "var(--danger)",
                        borderColor: "rgba(248,113,113,0.35)",
                      }}
                    >
                      Remove
                    </button>
                  </div>
                </li>
              ))}
            </ul>
            {stopsForSelected.length === 0 && (
              <div style={{ fontSize: 13, color: "var(--muted)" }}>No stops yet — search and add one above.</div>
            )}
          </section>
        </div>
      </div>
    );
  }

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
            Itineraries
          </div>
          <div style={{ fontWeight: 700, fontSize: 17 }}>Pick one to add stops</div>
        </div>
        <button type="button" onClick={onOpenExplore} style={{ ...btnSecondary, flexShrink: 0 }}>
          Open Explore
        </button>
      </header>

      <div style={{ flex: 1, overflow: "auto", padding: "16px 16px 28px", maxWidth: 560, margin: "0 auto", width: "100%" }}>
        <p style={{ margin: "0 0 16px", fontSize: 13, color: "var(--muted)", lineHeight: 1.55 }}>
          Create an itinerary, open it, then use <strong style={{ color: "var(--text)" }}>search</strong> to add
          places (OpenStreetMap Nominatim). You cannot add a stop until you are inside an itinerary.
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
          <h2 style={{ margin: "0 0 10px", fontSize: 15, fontWeight: 700 }}>New itinerary</h2>
          <form onSubmit={createItinerary} style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <input
              value={newGroupName}
              onChange={(ev) => setNewGroupName(ev.target.value)}
              placeholder="Name (e.g. Saturday in SF)"
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
              style={{
                border: "none",
                borderRadius: 10,
                padding: "10px 16px",
                fontWeight: 600,
                background: "linear-gradient(135deg, var(--accent), #e09a1f)",
                color: "#1a1204",
              }}
            >
              Create & open
            </button>
          </form>
        </section>

        <section
          style={{
            padding: 16,
            borderRadius: "var(--radius)",
            border: "1px solid var(--border)",
            background: "var(--panel)",
          }}
        >
          <h2 style={{ margin: "0 0 12px", fontSize: 15, fontWeight: 700 }}>Your itineraries</h2>
          <ul style={{ listStyle: "none", margin: 0, padding: 0 }}>
            {wishlistGroups.map((g) => {
              const count = wishlistItems.filter((x) => x.groupId === g.id).length;
              return (
                <li
                  key={g.id}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 10,
                    padding: "12px 0",
                    borderBottom: "1px solid rgba(255,255,255,0.06)",
                  }}
                >
                  <span
                    style={{
                      width: 10,
                      height: 10,
                      borderRadius: "50%",
                      background: g.color,
                      flexShrink: 0,
                    }}
                  />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontWeight: 700 }}>{g.name}</div>
                    <div style={{ fontSize: 11, color: "var(--muted)", marginTop: 2 }}>
                      {count} stop{count === 1 ? "" : "s"}
                    </div>
                  </div>
                  <button type="button" onClick={() => setSelectedId(g.id)} style={btnSecondary}>
                    Open
                  </button>
                </li>
              );
            })}
          </ul>
        </section>
      </div>
    </div>
  );
}
