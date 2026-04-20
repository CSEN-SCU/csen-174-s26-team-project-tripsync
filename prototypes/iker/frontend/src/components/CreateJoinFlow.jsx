import { useEffect, useState } from "react";
import { api } from "../lib/api.js";
import InterestPicker, { INTEREST_CATALOG } from "./InterestPicker.jsx";

const CITIES = ["Lisbon", "Barcelona", "San Francisco", "New York"];
const AVATARS = ["🙂", "🧳", "🥐", "📷", "🧭", "🥾", "🍷", "🎧", "🗝️", "🌻"];

// Three canned demo personas so a single presenter at the gallery walk can populate
// a session quickly. Maps exactly to the storyboard's trio: Priya / Marcus / Leah.
const DEMO_PERSONAS = [
  {
    key: "priya",
    name: "Priya",
    avatar: "📷",
    interests: ["culture", "views", "quirky"],
    vibe: "has the Google Doc, wants to see layers of the city",
  },
  {
    key: "marcus",
    name: "Marcus",
    avatar: "🎧",
    interests: ["food", "coffee", "outdoors"],
    vibe: "hungry, feet hurt, wants a bench",
  },
  {
    key: "leah",
    name: "Leah",
    avatar: "🥐",
    interests: ["food", "nightlife", "quirky"],
    vibe: "no tourist traps — locals' pastel de nata only",
  },
];

export default function CreateJoinFlow({ mode, defaultCode = "", onCancel, onSuccess }) {
  const isCreate = mode === "create";
  const [submitting, setSubmitting] = useState(false);
  const [err, setErr] = useState(null);

  // session fields
  const [city, setCity] = useState("Lisbon");
  const [code, setCode] = useState(defaultCode);

  // member fields
  const [name, setName] = useState("");
  const [avatar, setAvatar] = useState("🙂");
  const [interests, setInterests] = useState([]);
  const [vibe, setVibe] = useState("");

  useEffect(() => {
    setCode(defaultCode || "");
  }, [defaultCode]);

  const usePersona = (p) => {
    setName(p.name);
    setAvatar(p.avatar);
    setInterests(p.interests);
    setVibe(p.vibe);
  };

  const validate = () => {
    if (!name.trim()) {
      setErr("Give yourself a name — even 'P' works.");
      return false;
    }
    if (!isCreate) {
      if (!/^[A-Z0-9]{4}$/i.test(code.trim())) {
        setErr("Session codes are 4 letters/numbers (e.g. K3FX).");
        return false;
      }
    }
    setErr(null);
    return true;
  };

  const submit = async (extraJoin) => {
    if (!validate()) return;
    setSubmitting(true);
    try {
      if (isCreate) {
        const session = await api.createSession({ city });
        const joined = await api.join(session.code, {
          name: name.trim(),
          avatar,
          interests,
          vibe: vibe.trim(),
        });
        onSuccess(session.code, joined.member_id);
        // Optionally seed the demo trio in one click (for lone presenters).
        if (extraJoin === "trio") {
          for (const p of DEMO_PERSONAS) {
            if (p.name.toLowerCase() === name.trim().toLowerCase()) continue;
            try {
              await api.join(session.code, {
                name: p.name,
                avatar: p.avatar,
                interests: p.interests,
                vibe: p.vibe,
              });
            } catch (e) {
              console.warn("demo trio join failed", p, e);
            }
          }
        }
      } else {
        const joined = await api.join(code.trim().toUpperCase(), {
          name: name.trim(),
          avatar,
          interests,
          vibe: vibe.trim(),
        });
        onSuccess(code.trim().toUpperCase(), joined.member_id);
      }
    } catch (e) {
      if (e?.status === 404) {
        setErr(`No session found with code "${code.trim().toUpperCase()}".`);
      } else {
        setErr(e.message || String(e));
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="screen">
      <div className="card stack">
        <button className="ghost" onClick={onCancel} style={{ alignSelf: "flex-start" }}>
          ← Back
        </button>

        <div>
          <div className="kicker">
            {isCreate ? "Start a new session" : "Join with a code"}
          </div>
          <h1>{isCreate ? "Where are you three?" : "Hop into the group"}</h1>
          <p className="lede">
            {isCreate
              ? "Pick a city so Orbit knows where the group is standing. You can override exact coordinates later."
              : "Enter the 4-character code your friend sent, then tell Orbit a little about you."}
          </p>
        </div>

        {isCreate ? (
          <div>
            <div className="kicker">City</div>
            <div className="row wrap">
              {CITIES.map((c) => (
                <button
                  key={c}
                  className={c === city ? "primary" : ""}
                  onClick={() => setCity(c)}
                >
                  {c}
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div>
            <div className="kicker">Session code</div>
            <input
              className="mono"
              style={{ textTransform: "uppercase", letterSpacing: "0.3em" }}
              placeholder="K3FX"
              value={code}
              maxLength={4}
              onChange={(e) =>
                setCode(e.target.value.replace(/[^A-Za-z0-9]/g, "").toUpperCase())
              }
            />
          </div>
        )}

        <hr className="hr" />

        {isCreate && (
          <div>
            <div className="kicker">Load the storyboard trio</div>
            <div className="row wrap" style={{ gap: "0.4rem" }}>
              {DEMO_PERSONAS.map((p) => (
                <button
                  key={p.key}
                  onClick={() => usePersona(p)}
                  title={p.vibe}
                  style={{ fontSize: "0.88rem" }}
                >
                  <span style={{ marginRight: 6 }}>{p.avatar}</span>Be {p.name}
                </button>
              ))}
            </div>
            <p className="small muted" style={{ marginTop: 6 }}>
              Shortcut for solo gallery demos — fills your name, interests, and
              vibe to match a character from the storyboard.
            </p>
          </div>
        )}

        <div>
          <div className="kicker">Your name</div>
          <input
            placeholder="e.g. Priya"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>

        <div>
          <div className="kicker">Avatar</div>
          <div className="row wrap" style={{ gap: "0.3rem" }}>
            {AVATARS.map((a) => (
              <button
                key={a}
                onClick={() => setAvatar(a)}
                className={avatar === a ? "primary" : ""}
                style={{ fontSize: "1.1rem", padding: "0.35rem 0.55rem" }}
              >
                {a}
              </button>
            ))}
          </div>
        </div>

        <div>
          <div className="kicker">What are you into today?</div>
          <InterestPicker value={interests} onChange={setInterests} />
          <p className="small muted" style={{ marginTop: 6 }}>
            Pick 2–4. Orbit uses these to write your personal "why YOU" line per
            place. You can change them during the session.
          </p>
        </div>

        <div>
          <div className="kicker">One-line vibe (optional)</div>
          <input
            placeholder="e.g. hungry and tired, no more monuments"
            value={vibe}
            maxLength={120}
            onChange={(e) => setVibe(e.target.value)}
          />
        </div>

        {err && (
          <div
            className="small"
            style={{ color: "var(--accent)", fontWeight: 500 }}
          >
            {err}
          </div>
        )}

        <div className="row end" style={{ flexWrap: "wrap", gap: "0.5rem" }}>
          {isCreate && (
            <button
              disabled={submitting}
              onClick={() => submit("trio")}
              title="Create the session and auto-add the other two storyboard characters"
            >
              Create + add the other two as demo personas
            </button>
          )}
          <button className="primary" disabled={submitting} onClick={() => submit()}>
            {submitting
              ? "…"
              : isCreate
              ? "Create session & join"
              : "Join session"}
          </button>
        </div>

        {!isCreate && (
          <p className="small muted">
            Tip: the person who started the session can share the URL{" "}
            <code>#/s/{code || "XXXX"}</code> for one-tap joining.
          </p>
        )}

        <hr className="hr" />
        <p className="small muted">
          Heads up: this is a gallery-walk prototype. No accounts, no passwords.
          Anyone with the 4-char code can join your session until it's reset.
        </p>
        <p className="small muted">
          Visible interests: {INTEREST_CATALOG.map((i) => i.label).join(" · ")}.
        </p>
      </div>
    </div>
  );
}
