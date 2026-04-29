const fs = require("node:fs/promises");
const path = require("node:path");

const OUTPUT_PATH = path.join(__dirname, "data", "bay_area_pois.json");
const OVERPASS_URL = "https://overpass-api.de/api/interpreter";

const AREA_BOUNDS = {
  sf: {
    south: 37.7049,
    west: -122.527,
    north: 37.8349,
    east: -122.3482,
  },
  oakland: {
    south: 37.7012,
    west: -122.3558,
    north: 37.8847,
    east: -122.1144,
  },
  san_jose: {
    south: 37.1245,
    west: -122.0457,
    north: 37.4692,
    east: -121.5892,
  },
  berkeley: {
    south: 37.8357,
    west: -122.3674,
    north: 37.9067,
    east: -122.2342,
  },
};

const SEARCH_RULES = [
  { key: "tourism", value: "museum", category: "museum", tags: ["museum", "culture", "art"] },
  { key: "tourism", value: "attraction", category: "attraction", tags: ["culture", "history"] },
  { key: "tourism", value: "viewpoint", category: "viewpoint", tags: ["views", "nature"] },
  { key: "tourism", value: "gallery", category: "gallery", tags: ["art", "culture"] },
  { key: "historic", value: "*", category: "historic", tags: ["history", "culture"] },
  { key: "leisure", value: "park", category: "park", tags: ["nature", "walking", "family"] },
  { key: "amenity", value: "marketplace", category: "market", tags: ["food", "shopping"] },
];

function buildOverpassQuery() {
  const areaName = process.argv[2] || "sf";
  const areaBounds = AREA_BOUNDS[areaName];

  if (!areaBounds) {
    throw new Error(
      `Unknown area "${areaName}". Use one of: ${Object.keys(AREA_BOUNDS).join(", ")}`,
    );
  }

  const bounds = `${areaBounds.south},${areaBounds.west},${areaBounds.north},${areaBounds.east}`;
  const selectors = SEARCH_RULES.flatMap((rule) => {
    const tagSelector =
      rule.value === "*" ? `["${rule.key}"]` : `["${rule.key}"="${rule.value}"]`;

    return [
      `node${tagSelector}["name"](${bounds});`,
      `way${tagSelector}["name"](${bounds});`,
      `relation${tagSelector}["name"](${bounds});`,
    ];
  }).join("\n");

  return `
    [out:json][timeout:60];
    (
      ${selectors}
    );
    out center tags 250;
  `;
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

function findRule(tags) {
  return SEARCH_RULES.find((rule) => {
    if (!tags[rule.key]) {
      return false;
    }

    return rule.value === "*" || tags[rule.key] === rule.value;
  });
}

function getCoordinates(element) {
  if (element.lat !== undefined && element.lon !== undefined) {
    return { latitude: element.lat, longitude: element.lon };
  }

  if (element.center) {
    return { latitude: element.center.lat, longitude: element.center.lon };
  }

  return null;
}

function getCity(tags) {
  return (
    tags["addr:city"] ||
    tags["is_in:city"] ||
    tags["addr:suburb"] ||
    tags["addr:county"] ||
    "Bay Area"
  );
}

function buildDescription(name, category, city) {
  return `${name} is a ${category} point of interest in ${city}.`;
}

function toPoi(element) {
  const tags = element.tags || {};
  const name = tags.name;
  const coordinates = getCoordinates(element);
  const rule = findRule(tags);

  if (!name || !coordinates || !rule) {
    return null;
  }

  const city = getCity(tags);

  return {
    id: slugify(`${city}-${name}`),
    name,
    description: buildDescription(name, rule.category, city),
    city,
    category: rule.category,
    latitude: Number(coordinates.latitude.toFixed(6)),
    longitude: Number(coordinates.longitude.toFixed(6)),
    tags: [...new Set(rule.tags)],
  };
}

async function fetchPois() {
  const query = buildOverpassQuery();
  const response = await fetch(OVERPASS_URL, {
    method: "POST",
    headers: {
      "accept": "application/json",
      "content-type": "application/x-www-form-urlencoded; charset=UTF-8",
      "user-agent": "TripSync student project POI generator",
    },
    body: `data=${encodeURIComponent(query)}`,
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Overpass request failed with ${response.status}: ${body.slice(0, 500)}`);
  }

  const payload = await response.json();
  const poisById = new Map();

  payload.elements.map(toPoi).forEach((poi) => {
    if (poi) {
      poisById.set(poi.id, poi);
    }
  });

  return [...poisById.values()].sort((first, second) =>
    first.name.localeCompare(second.name),
  );
}

async function main() {
  const pois = await fetchPois();
  await fs.writeFile(OUTPUT_PATH, `${JSON.stringify(pois, null, 2)}\n`);
  console.log(`Wrote ${pois.length} POIs to ${OUTPUT_PATH}`);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
