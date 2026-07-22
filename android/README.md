# Rosterra — Native Android Staff App

Staff-only Android client for Rosterra. Behavioural source of truth:
[`../docs/android-staff/`](../docs/android-staff/README.md) (iOS Staff audit + roadmap).

## Status

| Phase | Status |
|-------|--------|
| A0 Foundations | In progress (scaffold + domain ports + Staff shell) |
| A1 Auth gates | Partial (login, forced password, profile completion, manager block) |
| A2 Staff listeners | Partial (shifts / timesheets / settings/app) |
| A3–A9 | Not started |

**Manager UI is out of scope** until Staff production gate S0.

## Stack

Kotlin · Jetpack Compose · Material 3 · Hilt · Navigation · Firestore persistent cache · Room (next) · FCM stub · Crashlytics plugin · OkHttp Worker client

## Setup

1. Install Android SDK 35 + JDK 17+.
2. Copy a real Firebase Android app config over the placeholder:

   ```bash
   cp app/google-services.json.example app/google-services.json
   # then replace with the Firebase console file for package:
   #   com.surainvestments.rosterra
   # and debug:
   #   com.surainvestments.rosterra.debug
   ```

3. From this directory:

   ```bash
   ./gradlew :app:assembleDebug :app:testDebugUnitTest
   ```

4. Open `android/` in Android Studio (Giraffe+/Ladybug) or sync Gradle.

## Package

`com.surainvestments.rosterra` (debug suffix `.debug`)

## Notes

- Placeholder `google-services.json` lets the project compile; Auth/Firestore need the real Firebase Android apps registered for both package names.
- Staff repository queries are uid-scoped. Managers who sign in see a blocked screen.
