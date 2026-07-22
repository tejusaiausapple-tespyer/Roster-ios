package com.surainvestments.rosterra.data.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM entry point. Full deep-link routing lands in roadmap phase A8;
 * for now we accept messages so token registration can proceed later.
 */
class RosterraMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Token sync to users/{uid}/notificationTokens is wired in A8.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Foreground handling + AppRouter parity in A8.
    }
}
