export const INTEREST_CATALOG = [
  { id: "food", emoji: "🍽️", label: "Food" },
  { id: "coffee", emoji: "☕", label: "Coffee" },
  { id: "views", emoji: "🌇", label: "Views" },
  { id: "culture", emoji: "🏛️", label: "Culture" },
  { id: "outdoors", emoji: "🌿", label: "Outdoors" },
  { id: "nightlife", emoji: "🍷", label: "Nightlife" },
  { id: "shopping", emoji: "🛍️", label: "Shopping" },
  { id: "quirky", emoji: "🎪", label: "Quirky" },
];

export default function InterestPicker({ value = [], onChange }) {
  const set = new Set(value);
  const toggle = (id) => {
    const next = new Set(set);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    onChange(Array.from(next));
  };
  return (
    <div className="interest-grid">
      {INTEREST_CATALOG.map((it) => (
        <label
          key={it.id}
          className={`interest-chip${set.has(it.id) ? " on" : ""}`}
          onClick={(e) => {
            e.preventDefault();
            toggle(it.id);
          }}
        >
          <span role="img" aria-hidden>
            {it.emoji}
          </span>
          <span>{it.label}</span>
        </label>
      ))}
    </div>
  );
}
