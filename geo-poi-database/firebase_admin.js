const admin = require("firebase-admin");

const PLACEHOLDER_PROJECT_ID = "your-firebase-project-id";
const PLACEHOLDER_CREDENTIALS_PATH = "C:\\path\\to";

function hasCloudProjectId() {
  return (
    Boolean(process.env.GCLOUD_PROJECT) &&
    process.env.GCLOUD_PROJECT !== PLACEHOLDER_PROJECT_ID
  );
}

function hasCredentialsFilePath() {
  return (
    Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS) &&
    !process.env.GOOGLE_APPLICATION_CREDENTIALS.includes(PLACEHOLDER_CREDENTIALS_PATH)
  );
}

function parseServiceAccountJson() {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return null;
  }

  try {
    return JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  } catch (error) {
    throw new Error(
      `FIREBASE_SERVICE_ACCOUNT_JSON must be valid service account JSON: ${error.message}`,
    );
  }
}

function getMissingFirebaseConfigMessage() {
  return [
    "Firestore cloud access is not configured.",
    "Set GCLOUD_PROJECT to the Firebase project ID.",
    "Then provide credentials with either:",
    "- GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json",
    "- FIREBASE_SERVICE_ACCOUNT_JSON='{\"type\":\"service_account\",...}'",
  ].join("\n");
}

function getFirebaseAdminApp() {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  if (!hasCloudProjectId()) {
    throw new Error(getMissingFirebaseConfigMessage());
  }

  const serviceAccount = parseServiceAccountJson();

  if (serviceAccount) {
    return admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId: process.env.GCLOUD_PROJECT,
    });
  }

  if (hasCredentialsFilePath()) {
    return admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: process.env.GCLOUD_PROJECT,
    });
  }

  throw new Error(getMissingFirebaseConfigMessage());
}

function getFirestore() {
  delete process.env.FIRESTORE_EMULATOR_HOST;
  return admin.firestore(getFirebaseAdminApp());
}

module.exports = {
  getFirebaseAdminApp,
  getFirestore,
  getMissingFirebaseConfigMessage,
};
