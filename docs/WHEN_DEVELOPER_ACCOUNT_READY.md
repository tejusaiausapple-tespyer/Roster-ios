# When Apple Developer account is ready

**Status:** Waiting — user will say when paid Apple Developer verification is complete.

Until then, the app runs on a **personal team** without Push Notifications (that capability is removed from entitlements on purpose).

---

## What to do when the account is verified

Tell the agent: *"Apple Developer account is ready — re-enable push."*

Then:

### 1. Apple Developer portal
- Confirm App ID `com.surainvestments.roster` exists (or create it).
- Enable **Push Notifications** for that App ID.
- Create an **APNs key** (or certificate) in Certificates, Identifiers & Profiles if not already done.
- In Firebase Console → Project Settings → Cloud Messaging → **Apple app configuration**, upload the APNs key (.p8) for the iOS app.

### 2. App code (one-line activation + FCM hookup)
- Set `AppConfig.pushEnabled = true` (`RosterStaff/Services/AppConfig.swift`).
  Everything downstream is already wired: authorization prompt, APNs
  registration, token upload to `users/{uid}.fcmToken`, foreground /
  background / terminated handling, and notification haptics.
- In `NotificationService.updateAPNSToken(_:)`, replace the raw-hex fallback
  with `Messaging.messaging().apnsToken = deviceToken` and add a
  `MessagingDelegate` that forwards FCM tokens to `updateFCMToken(_:)`
  (marked with comments in the file).

### 3. Xcode / project
- Set `DEVELOPMENT_TEAM` in `project.yml` to your paid team ID (or pick the team in Xcode Signing & Capabilities).
- In `project.yml`, re-add the FirebaseMessaging dependency:
  ```yaml
  - package: Firebase
    product: FirebaseMessaging
  ```
- Restore `AppDelegate.swift` and `NotificationService.swift` FCM/APNs code (or ask the agent to re-enable).
- Re-enable push in `RosterStaff/Resources/RosterStaff.entitlements`:
  ```xml
  <key>aps-environment</key>
  <string>development</string>   <!-- use "production" for App Store / TestFlight -->
  ```
- Re-add to `RosterStaff/Resources/Info.plist`:
  ```xml
  <key>UIBackgroundModes</key>
  <array>
    <string>remote-notification</string>
  </array>
  ```
- In `project.yml` target settings, restore:
  ```yaml
  CODE_SIGN_ENTITLEMENTS: RosterStaff/Resources/RosterStaff.entitlements
  ```
- Run `xcodegen generate` from the project root.
- In Xcode: target **RosterStaff** → Signing & Capabilities → **+ Capability** → Push Notifications (if not auto-added).

### 4. Backend (already done)
- `firestore.rules` already allows `ios-native` for notification token `platform` (user deployed rules).

### 5. Verify
- Build on a **real device** (simulator does not deliver real APNs).
- Sign in as staff → app should register FCM token to `users/{uid}/notificationTokens/`.
- Confirm a test push (e.g. manager approves timesheet) arrives.

---

## What works today (without paid account)

- Sign in, roster, submit hours, absence, history, availability, account, Face ID lock, calendar add, Firestore sync.
- **Not available until push is re-enabled:** remote push notifications (foreground toasts from FCM still won’t work without APNs).
