const assert = require("node:assert/strict");
const { createRequire } = require("node:module");
const path = require("node:path");
const test = require("node:test");

const geoPoiRequire = createRequire(
  path.join(__dirname, "../geo-poi-database/package.json"),
);
const admin = geoPoiRequire("firebase-admin");
const geofire = geoPoiRequire("geofire-common");

delete process.env.FIRESTORE_EMULATOR_HOST;

if (
  !process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  process.env.GOOGLE_APPLICATION_CREDENTIALS.includes("C:\\path\\to")
) {
  throw new Error(
    "Set GOOGLE_APPLICATION_CREDENTIALS to your downloaded service account JSON file before running this cloud Firestore test.",
  );
}

if (
  !process.env.GCLOUD_PROJECT ||
  process.env.GCLOUD_PROJECT === "your-firebase-project-id"
) {
  throw new Error(
    "Set GCLOUD_PROJECT to your real Firebase project ID before running this cloud Firestore test.",
  );
}

const app = admin.initializeApp({
  projectId: process.env.GCLOUD_PROJECT,
});

const db = admin.firestore(app);

function distanceInMiles(origin, destination) {
  const earthRadiusMiles = 3958.8;
  const degreesToRadians = Math.PI / 180;

  const latitudeDelta =
    (destination.latitude - origin.latitude) * degreesToRadians;
  const longitudeDelta =
    (destination.longitude - origin.longitude) * degreesToRadians;

  const originLatitude = origin.latitude * degreesToRadians;
  const destinationLatitude = destination.latitude * degreesToRadians;

  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(originLatitude) *
      Math.cos(destinationLatitude) *
      Math.sin(longitudeDelta / 2) ** 2;

  return (
    2 * earthRadiusMiles * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
  );
}

async function queryPois({ location, radiusMiles, preferences }) {
  const center = [location.latitude, location.longitude];
  const radiusMeters = radiusMiles * 1609.344;
  const bounds = geofire.geohashQueryBounds(center, radiusMeters);

  const snapshots = await Promise.all(
    bounds.map(([start, end]) =>
      db
        .collection("pois")
        .orderBy("geo.geohash")
        .startAt(start)
        .endAt(end)
        .get(),
    ),
  );

  const uniquePois = new Map();

  snapshots.forEach((snapshot) => {
    snapshot.docs.forEach((doc) => {
      const data = doc.data();
      const geopoint = data.geo?.geopoint;

      if (!geopoint) {
        return;
      }

      const poi = {
        id: doc.id,
        name: data.name,
        tags: data.tags || [],
        location: {
          latitude: geopoint.latitude,
          longitude: geopoint.longitude,
        },
      };

      uniquePois.set(doc.id, poi);
    });
  });

  return [...uniquePois.values()]
    .map((poi) => {
      const preferenceScore = poi.tags.filter((tag) =>
        preferences.includes(tag),
      ).length;

      return {
        ...poi,
        distanceMiles: distanceInMiles(location, poi.location),
        preferenceScore,
      };
    })
    .filter((poi) => poi.distanceMiles <= radiusMiles && poi.preferenceScore > 0)
    .sort(
      (first, second) =>
        second.preferenceScore - first.preferenceScore ||
        first.distanceMiles - second.distanceMiles,
    );
}

test("geo POI database returns expected POIs for a valid location query", async () => {
  const jimmyHendrixHouseLocation = {
    latitude: 37.770058,
    longitude: -122.447466,
  };

  const results = await queryPois({
    location: jimmyHendrixHouseLocation,
    radiusMiles: 1.2,
    preferences: ["culture"],
  });

  assert.ok(
    results.some((poi) => poi.id === "bay-area-jimmy-hendrix-house"),
    "Expected Bay Area Jimmy Hendrix House to be included in culture POI results",
  );
});
