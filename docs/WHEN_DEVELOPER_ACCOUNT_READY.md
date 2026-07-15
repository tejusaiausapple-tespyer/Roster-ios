# Apple Developer account — done

**Status:** Resolved 2026-07-15. Paid team `GS2KGPX9P8` is wired into
`project.yml`, and push notifications are fully enabled end-to-end:

- `AppConfig.pushEnabled = true`
- `NotificationService` registers with APNs, hands the device token to FCM
  (`Messaging.messaging().apnsToken`), and receives the FCM registration
  token via `MessagingDelegate.didReceiveRegistrationToken`, which is what
  gets uploaded to `users/{uid}.fcmToken`.
- `RosterStaff.entitlements` has `aps-environment: production` and
  Associated Domains (`webcredentials:sura-roster.com`) for passkeys.
- `Info.plist` declares the `remote-notification` background mode.

Remaining manual step in the Apple Developer portal / Firebase Console: make
sure the APNs key (.p8) for team `GS2KGPX9P8` is uploaded under Firebase
Console → Project Settings → Cloud Messaging → Apple app configuration —
this can't be done from code. Verify by signing in on a real device (the
simulator doesn't deliver real APNs) and confirming a test push arrives.
