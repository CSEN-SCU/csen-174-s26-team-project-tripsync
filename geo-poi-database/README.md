# Geo POI Firebase Tests

The geo POI integration test reads from the real Firestore `pois` collection. It does not seed data during the test, so the Firebase project must already contain the expected POI documents.

## Local Setup

Set the Firebase project ID:

```powershell
$env:GCLOUD_PROJECT = "your-real-firebase-project-id"
```

Then provide service account credentials using one of these options.

For local development, point `GOOGLE_APPLICATION_CREDENTIALS` at a downloaded service account JSON file:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\absolute\path\to\service-account.json"
npm test
```

For CI or environments where creating a file is inconvenient, provide the full service account JSON in `FIREBASE_SERVICE_ACCOUNT_JSON`:

```powershell
$env:FIREBASE_SERVICE_ACCOUNT_JSON = Get-Content "C:\absolute\path\to\service-account.json" -Raw
npm test
```

## GitHub Actions Secrets

Configure these repository secrets:

- `GCLOUD_PROJECT`: the Firebase project ID.
- `FIREBASE_SERVICE_ACCOUNT_JSON`: the full contents of the service account JSON file.

The service account needs permission to read the Firestore `pois` collection. The test currently expects the `bay-area-jimmy-hendrix-house` document to exist with a `culture` tag and `geo.geopoint` / `geo.geohash` fields.
