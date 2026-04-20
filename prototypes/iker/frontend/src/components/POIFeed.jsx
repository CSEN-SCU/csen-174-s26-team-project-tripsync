function category_icon(c) {
  const map = {
    food: "🍽️",
    coffee: "☕",
    views: "🌇",
    culture: "🏛️",
    outdoors: "🌿",
    nightlife: "🍷",
    shopping: "🛍️",
    quirky: "🎪",
    place: "📍",
  };
  return map[c] || "📍";
}

function consensus(rx, memberCount) {
  const love = rx?.love || 0;
  const maybe = rx?.maybe || 0;
  const nope = rx?.nope || 0;
  const score = love * 2 + maybe * 1 - nope * 2;
  const total = love + maybe + nope;
  // Heuristic: at least half the group reacted positively and no majority vetoed.
  const reached =
    memberCount > 0 &&
    love >= Math.ceil(memberCount / 2) &&
    nope < Math.ceil(memberCount / 2);
  return { score, total, reached };
}

export default function POIFeed({ state, me, actions }) {
  const { pois, members, destination } = state;
  const memberById = Object.fromEntries(members.map((m) => [m.id, m]));

  if (!pois.length) {
    return (
      <div className="card" style={{ maxWidth: "none" }}>
        <div className="kicker">Picks</div>
        <h2 style={{ marginBottom: 4 }}>No group picks yet</h2>
        <p className="muted small">
          Once you and your friends have joined, tap{" "}
          <strong>Get group picks</strong> in the dock below. Orbit will read
          everyone's interests and surface 4–5 spots with a tailored "why YOU"
          line per person.
        </p>
      </div>
    );
  }

  const sorted = [...pois].sort((a, b) => {
    const ca = consensus(a.reactions, members.length);
    const cb = consensus(b.reactions, members.length);
    return cb.score - ca.score;
  });

  return (
    <div className="poi-list">
      {sorted.map((p, idx) => {
        const rank = pois.findIndex((x) => x.id === p.id) + 1;
        const mineReaction = me ? p.member_reactions?.[String(me.id)] : null;
        const con = consensus(p.reactions, members.length);
        const isPicked = destination && destination.id === p.id;

        const whyRows = Object.entries(p.why || {})
          .map(([mid, reason]) => ({
            mid,
            reason,
            member: memberById[Number(mid)],
          }))
          .filter((x) => x.member)
          // Show the current user's line first.
          .sort((a, b) => {
            if (me && String(me.id) === a.mid) return -1;
            if (me && String(me.id) === b.mid) return 1;
            return a.member.name.localeCompare(b.member.name);
          });

        return (
          <article
            key={p.id}
            className="poi-card"
            style={{
              borderColor: isPicked ? "var(--ok)" : undefined,
              background: isPicked ? "#edf7f1" : undefined,
            }}
          >
            <div className="poi-head">
              <div>
                <span className="muted small">
                  {rank}. {category_icon(p.category)} {p.category}
                </span>
                <div className="poi-title">{p.name}</div>
              </div>
              {isPicked && (
                <span
                  className="badge"
                  style={{ background: "#cde9d7", color: "var(--ok)" }}
                >
                  Group pick ✓
                </span>
              )}
            </div>

            <div className="poi-meta">
              {p.walk_minutes} min walk
            </div>
            <p className="poi-blurb">{p.blurb}</p>

            {whyRows.length > 0 && (
              <div className="why-block">
                {whyRows.map(({ mid, reason, member }) => {
                  const isMe = me && String(me.id) === mid;
                  return (
                    <div
                      key={mid}
                      className={`why-row${isMe ? " for-me" : ""}`}
                    >
                      <span className="who">
                        {member.avatar} {member.name}
                        {isMe ? " (you)" : ""}:
                      </span>
                      <span>{reason}</span>
                    </div>
                  );
                })}
              </div>
            )}

            <div className="reactions">
              {me && (
                <>
                  <button
                    className={`react-btn${mineReaction === "love" ? " on-love" : ""}`}
                    onClick={() => actions.react(p.id, "love")}
                  >
                    ❤️ love
                  </button>
                  <button
                    className={`react-btn${mineReaction === "maybe" ? " on-maybe" : ""}`}
                    onClick={() => actions.react(p.id, "maybe")}
                  >
                    🤔 maybe
                  </button>
                  <button
                    className={`react-btn${mineReaction === "nope" ? " on-nope" : ""}`}
                    onClick={() => actions.react(p.id, "nope")}
                  >
                    👎 nope
                  </button>
                </>
              )}

              <span className="react-tally">
                ❤️ {p.reactions.love} · 🤔 {p.reactions.maybe} · 👎{" "}
                {p.reactions.nope}
              </span>
            </div>

            {con.reached && !isPicked && (
              <div style={{ marginTop: 8 }} className="row">
                <span className="consensus-nudge">
                  ✨ Group is leaning this way
                </span>
                <button
                  className="primary"
                  style={{ marginLeft: "auto" }}
                  onClick={() => actions.pick(p.id)}
                >
                  Let's go here
                </button>
              </div>
            )}

            {!con.reached && !isPicked && (
              <div className="row" style={{ marginTop: 8 }}>
                <button
                  className="ghost small"
                  style={{ marginLeft: "auto" }}
                  onClick={() => actions.pick(p.id)}
                  title="Override consensus and lock this as the destination"
                >
                  Pick anyway →
                </button>
              </div>
            )}
          </article>
        );
      })}
    </div>
  );
}
