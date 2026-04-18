/**
 * Six user interests — each has a unique color used for chips, map markers, and list dots.
 * POIs are assigned the first matching theme from OSM tags + category text.
 */

export const INTEREST_ORDER = [
  "history",
  "food",
  "outdoors",
  "art",
  "tech",
  "hidden gems",
];

/** Distinct hues — WCAG-friendly on dark UI */
export const INTEREST_COLORS = {
  history: "#3b82f6",
  food: "#f97316",
  outdoors: "#22c55e",
  art: "#a855f7",
  tech: "#eab308",
  "hidden gems": "#06b6d4",
};

const RULES = [
  [
    "history",
    [
      "historic",
      "history",
      "memorial",
      "monument",
      "heritage",
      "basilica",
      "mission",
      "abbey",
      "ruins",
      "archae",
      "castle",
      "church",
      "chapel",
      "grave",
      "cemetery",
    ],
  ],
  [
    "food",
    [
      "restaurant",
      "cafe",
      "café",
      "food",
      "bakery",
      "pub",
      "brewery",
      "kitchen",
      "dining",
      "fast_food",
      "ice_cream",
      "amenity=bar",
    ],
  ],
  [
    "outdoors",
    [
      "leisure=park",
      "park",
      "peak",
      "beach",
      "garden",
      "forest",
      "trail",
      "viewpoint",
      "natural=",
      "hiking",
      "playground",
      "nature",
    ],
  ],
  [
    "art",
    [
      "museum",
      "gallery",
      "theatre",
      "theater",
      "arts_centre",
      "artwork",
      "sculpture",
      "cinema",
      "arts",
    ],
  ],
  [
    "tech",
    [
      "technology",
      "science",
      "observatory",
      "planetarium",
      "computer",
      "telecom",
      "innovation",
      "intel",
      "silicon",
      "chip",
    ],
  ],
];

/**
 * @param {object} poi - nearby row with tags (string[]), category (string), name (string)
 * @returns {keyof typeof INTEREST_COLORS}
 */
export function poiInterestTheme(poi) {
  const tags = Array.isArray(poi.tags) ? poi.tags : [];
  const blob = `${tags.join(" ")} ${poi.category || ""} ${poi.name || ""}`.toLowerCase();

  for (const [theme, keywords] of RULES) {
    if (keywords.some((k) => blob.includes(k.trim().toLowerCase()))) {
      return theme;
    }
  }
  return "hidden gems";
}

export function interestColor(theme) {
  return INTEREST_COLORS[theme] || INTEREST_COLORS["hidden gems"];
}

/**
 * Map + lists only include POIs whose inferred theme is one of the selected chips.
 * @param {string[]} selected - e.g. ["history", "food"]
 */
export function poiMatchesSelectedInterests(poi, selected) {
  if (!selected || selected.length === 0) return true;
  const theme = poiInterestTheme(poi);
  return selected.includes(theme);
}
