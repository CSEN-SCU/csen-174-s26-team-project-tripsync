const fs = require("node:fs/promises");
const path = require("node:path");
const admin = require("firebase-admin");
const geofire = require("geofire-common");

function configureEnvironment({ useCloud = false } = {}) {
  if (useCloud) {
    delete process.env.FIRESTORE_EMULATOR_HOST;

    if (
      !process.env.GOOGLE_APPLICATION_CREDENTIALS ||
      process.env.GOOGLE_APPLICATION_CREDENTIALS.includes("C:\\path\\to")
    ) {
      throw new Error(
        "Set GOOGLE_APPLICATION_CREDENTIALS to your downloaded service account JSON file before running seed:cloud.",
      );
    }

    if (
      !process.env.GCLOUD_PROJECT ||
      process.env.GCLOUD_PROJECT === "your-firebase-project-id"
    ) {
      throw new Error(
        "Set GCLOUD_PROJECT to your real Firebase project ID before running seed:cloud.",
      );
    }

    return;
  }

  process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
  process.env.GCLOUD_PROJECT ??= "demo-no-project";
}

function getFirestore() {
  if (!admin.apps.length) {
    admin.initializeApp({
      projectId: process.env.GCLOUD_PROJECT,
    });
  }

  return admin.firestore();
}

async function loadPois() {
  const poisPath = path.join(__dirname, "data", "bay_area_pois.json");
  const poisJson = await fs.readFile(poisPath, "utf8");

  return JSON.parse(poisJson);
}

function validatePoi(poi) {
  const requiredFields = ["id", "name", "latitude", "longitude", "tags"];
  const missingFields = requiredFields.filter((field) => poi[field] === undefined);

  if (missingFields.length > 0) {
    throw new Error(`POI ${poi.id || "(missing id)"} is missing: ${missingFields.join(", ")}`);
  }

  if (!Array.isArray(poi.tags)) {
    throw new Error(`POI ${poi.id} tags must be an array`);
  }
}

async function seedPois(options) {
  configureEnvironment(options);

  const db = getFirestore();
  const pois = await loadPois();

  await Promise.all(
    pois.map((poi) => {
      validatePoi(poi);

      return db
        .collection("pois")
        .doc(poi.id)
        .set({
          name: poi.name,
          description: poi.description || "",
          city: poi.city || "",
          category: poi.category || "",
          tags: poi.tags,
          geo: {
            geopoint: new admin.firestore.GeoPoint(poi.latitude, poi.longitude),
            geohash: geofire.geohashForLocation([poi.latitude, poi.longitude]),
          },
        });
    }),
  );

  return pois.length;
}

if (require.main === module) {
  const useCloud = process.argv.includes("--cloud");

  seedPois({ useCloud })
    .then((count) => {
      console.log(`Seeded ${count} POIs into Firestore.`);
      return admin.app().delete();
    })
    .catch((error) => {
      console.error(error);
      process.exitCode = 1;
    });
}

module.exports = {
  seedPois,
};
