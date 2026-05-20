#!/usr/bin/env bash
# Writes gitignored Android/iOS Firebase config from environment variables.
# CI: values come from GitHub Actions secrets. Local: export vars or use app/.env
# with the same names, then run this script before flutter build.

set -euo pipefail

# Load app/.env when present (local dev).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

require() {
  if [ -z "${!1:-}" ]; then
    echo "Missing required env var: $1" >&2
    exit 1
  fi
}

for v in \
  FIREBASE_PROJECT_ID \
  FIREBASE_MESSAGING_SENDER_ID \
  FIREBASE_STORAGE_BUCKET \
  FIREBASE_ANDROID_API_KEY \
  FIREBASE_ANDROID_APP_ID \
  FIREBASE_ANDROID_OAUTH_CLIENT_ID \
  FIREBASE_IOS_API_KEY \
  FIREBASE_IOS_APP_ID \
  FIREBASE_IOS_CLIENT_ID; do
  require "$v"
done

ANDROID_JSON="$ROOT/android/app/google-services.json"
IOS_PLIST="$ROOT/ios/Runner/GoogleService-Info.plist"
IOS_REVERSED="com.googleusercontent.apps.${FIREBASE_IOS_CLIENT_ID%%.apps.googleusercontent.com}"

mkdir -p "$(dirname "$ANDROID_JSON")" "$(dirname "$IOS_PLIST")"

cat >"$ANDROID_JSON" <<EOF
{
  "project_info": {
    "project_number": "${FIREBASE_MESSAGING_SENDER_ID}",
    "project_id": "${FIREBASE_PROJECT_ID}",
    "storage_bucket": "${FIREBASE_STORAGE_BUCKET}"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "${FIREBASE_ANDROID_APP_ID}",
        "android_client_info": {
          "package_name": "edu.scu.orbit"
        }
      },
      "oauth_client": [
        {
          "client_id": "${FIREBASE_ANDROID_OAUTH_CLIENT_ID}",
          "client_type": 3
        }
      ],
      "api_key": [
        {
          "current_key": "${FIREBASE_ANDROID_API_KEY}"
        }
      ],
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": [
            {
              "client_id": "${FIREBASE_ANDROID_OAUTH_CLIENT_ID}",
              "client_type": 3
            },
            {
              "client_id": "${FIREBASE_IOS_CLIENT_ID}",
              "client_type": 2,
              "ios_info": {
                "bundle_id": "edu.scu.orbit"
              }
            }
          ]
        }
      }
    }
  ],
  "configuration_version": "1"
}
EOF

cat >"$IOS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>${FIREBASE_IOS_CLIENT_ID}</string>
	<key>REVERSED_CLIENT_ID</key>
	<string>${IOS_REVERSED}</string>
	<key>API_KEY</key>
	<string>${FIREBASE_IOS_API_KEY}</string>
	<key>GCM_SENDER_ID</key>
	<string>${FIREBASE_MESSAGING_SENDER_ID}</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>edu.scu.orbit</string>
	<key>PROJECT_ID</key>
	<string>${FIREBASE_PROJECT_ID}</string>
	<key>STORAGE_BUCKET</key>
	<string>${FIREBASE_STORAGE_BUCKET}</string>
	<key>IS_ADS_ENABLED</key>
	<false></false>
	<key>IS_ANALYTICS_ENABLED</key>
	<false></false>
	<key>IS_APPINVITE_ENABLED</key>
	<true></true>
	<key>IS_GCM_ENABLED</key>
	<true></true>
	<key>IS_SIGNIN_ENABLED</key>
	<true></true>
	<key>GOOGLE_APP_ID</key>
	<string>${FIREBASE_IOS_APP_ID}</string>
</dict>
</plist>
EOF

echo "Wrote $ANDROID_JSON and $IOS_PLIST"
