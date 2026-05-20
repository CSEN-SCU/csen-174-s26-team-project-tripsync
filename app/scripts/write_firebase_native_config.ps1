# Writes gitignored Android/iOS Firebase config from environment variables.
# Local: set vars in app/.env, then: Get-Content .env | ForEach-Object { ... }; .\scripts\write_firebase_native_config.ps1
# Or run from repo CI workflow (secrets injected as env).

param(
  [string]$AppRoot = (Split-Path $PSScriptRoot -Parent)
)

function Require-Env([string]$Name) {
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Missing required environment variable: $Name"
  }
  return $value
}

$required = @(
  'FIREBASE_PROJECT_ID',
  'FIREBASE_MESSAGING_SENDER_ID',
  'FIREBASE_STORAGE_BUCKET',
  'FIREBASE_ANDROID_API_KEY',
  'FIREBASE_ANDROID_APP_ID',
  'FIREBASE_ANDROID_OAUTH_CLIENT_ID',
  'FIREBASE_IOS_API_KEY',
  'FIREBASE_IOS_APP_ID',
  'FIREBASE_IOS_CLIENT_ID'
)
foreach ($name in $required) {
  Require-Env $name | Out-Null
}

$projectId = Require-Env 'FIREBASE_PROJECT_ID'
$senderId = Require-Env 'FIREBASE_MESSAGING_SENDER_ID'
$storageBucket = Require-Env 'FIREBASE_STORAGE_BUCKET'
$androidKey = Require-Env 'FIREBASE_ANDROID_API_KEY'
$androidAppId = Require-Env 'FIREBASE_ANDROID_APP_ID'
$androidOauth = Require-Env 'FIREBASE_ANDROID_OAUTH_CLIENT_ID'
$iosKey = Require-Env 'FIREBASE_IOS_API_KEY'
$iosAppId = Require-Env 'FIREBASE_IOS_APP_ID'
$iosClientId = Require-Env 'FIREBASE_IOS_CLIENT_ID'
$iosReversed = "com.googleusercontent.apps.$($iosClientId.Split('.')[0])"

$androidJson = Join-Path $AppRoot 'android\app\google-services.json'
$iosPlist = Join-Path $AppRoot 'ios\Runner\GoogleService-Info.plist'
New-Item -ItemType Directory -Force -Path (Split-Path $androidJson) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $iosPlist) | Out-Null

@{
  project_info = @{
    project_number = $senderId
    project_id = $projectId
    storage_bucket = $storageBucket
  }
  client = @(
    @{
      client_info = @{
        mobilesdk_app_id = $androidAppId
        android_client_info = @{ package_name = 'edu.scu.orbit' }
      }
      oauth_client = @(
        @{ client_id = $androidOauth; client_type = 3 }
      )
      api_key = @(
        @{ current_key = $androidKey }
      )
      services = @{
        appinvite_service = @{
          other_platform_oauth_client = @(
            @{ client_id = $androidOauth; client_type = 3 },
            @{
              client_id = $iosClientId
              client_type = 2
              ios_info = @{ bundle_id = 'edu.scu.orbit' }
            }
          )
        }
      }
    }
  )
  configuration_version = '1'
} | ConvertTo-Json -Depth 10 | Set-Content -Path $androidJson -Encoding utf8

$plist = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>$iosClientId</string>
	<key>REVERSED_CLIENT_ID</key>
	<string>$iosReversed</string>
	<key>API_KEY</key>
	<string>$iosKey</string>
	<key>GCM_SENDER_ID</key>
	<string>$senderId</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>edu.scu.orbit</string>
	<key>PROJECT_ID</key>
	<string>$projectId</string>
	<key>STORAGE_BUCKET</key>
	<string>$storageBucket</string>
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
	<string>$iosAppId</string>
</dict>
</plist>
"@
Set-Content -Path $iosPlist -Value $plist -Encoding utf8
Write-Host "Wrote $androidJson and $iosPlist"
