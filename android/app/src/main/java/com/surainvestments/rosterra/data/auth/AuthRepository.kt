package com.surainvestments.rosterra.data.auth

import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FirebaseFirestore
import com.surainvestments.rosterra.core.model.AppUser
import com.surainvestments.rosterra.core.model.UserRole
import com.surainvestments.rosterra.core.model.UserStatus
import com.surainvestments.rosterra.data.prefs.SessionPrefs
import com.surainvestments.rosterra.data.worker.WorkerApiClient
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.time.format.DateTimeFormatter

@Singleton
class AuthRepository @Inject constructor(
    private val prefs: SessionPrefs,
    private val worker: WorkerApiClient,
) {
    private val auth: FirebaseAuth get() = FirebaseAuth.getInstance()
    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    val authState: Flow<FirebaseUser?> = callbackFlow {
        val listener = FirebaseAuth.AuthStateListener { trySend(it.currentUser) }
        auth.addAuthStateListener(listener)
        awaitClose { auth.removeAuthStateListener(listener) }
    }

    val currentUser: FirebaseUser? get() = auth.currentUser

    suspend fun signIn(email: String, password: String, remember: Boolean): AppUser {
        val result = auth.signInWithEmailAndPassword(email.trim(), password).await()
        val uid = result.user?.uid ?: error("Sign-in failed")
        val profile = fetchUser(uid)
        if (!profile.isActiveAccount) {
            auth.signOut()
            error("This account is ${profile.status.raw}. Contact your manager.")
        }
        if (profile.isManager) {
            // Staff app milestone: block managers from the Staff shell.
            // Keep auth so they can sign out cleanly from the blocked screen.
        }
        prefs.setRememberedEmail(email.trim(), remember)
        prefs.markManualLogin()
        prefs.setDeviceAuthVerified(true)
        db.collection("users").document(uid)
            .update("lastLoginAt", DateTimeFormatter.ISO_INSTANT.format(Instant.now()))
            .await()
        return profile
    }

    suspend fun sendPasswordReset(email: String) {
        auth.sendPasswordResetEmail(email.trim()).await()
    }

    suspend fun signOut() {
        auth.signOut()
        prefs.clearSessionFlags()
    }

    suspend fun fetchUser(uid: String = currentUser?.uid ?: error("Not signed in")): AppUser {
        val snap = db.collection("users").document(uid).get().await()
        if (!snap.exists()) error("User profile missing")
        return AppUser(
            id = uid,
            fullName = snap.getString("fullName").orEmpty(),
            email = snap.getString("email").orEmpty(),
            phone = snap.getString("phone"),
            role = UserRole.fromRaw(snap.getString("role")),
            status = UserStatus.fromRaw(snap.getString("status")),
            mustChangePassword = snap.getBoolean("mustChangePassword") == true,
            needsSetup = snap.getBoolean("needsSetup") == true,
            profileUpdateRequired = snap.getBoolean("profileUpdateRequired") == true,
            dob = snap.getString("dob"),
            address = snap.getString("address"),
            employeeId = snap.getString("employeeId"),
        )
    }

    fun observeUser(uid: String): Flow<AppUser?> = callbackFlow {
        val reg = db.collection("users").document(uid)
            .addSnapshotListener { snap, error ->
                if (error != null) {
                    trySend(null)
                    return@addSnapshotListener
                }
                if (snap == null || !snap.exists()) {
                    trySend(null)
                    return@addSnapshotListener
                }
                trySend(
                    AppUser(
                        id = uid,
                        fullName = snap.getString("fullName").orEmpty(),
                        email = snap.getString("email").orEmpty(),
                        phone = snap.getString("phone"),
                        role = UserRole.fromRaw(snap.getString("role")),
                        status = UserStatus.fromRaw(snap.getString("status")),
                        mustChangePassword = snap.getBoolean("mustChangePassword") == true,
                        needsSetup = snap.getBoolean("needsSetup") == true,
                        profileUpdateRequired = snap.getBoolean("profileUpdateRequired") == true,
                        dob = snap.getString("dob"),
                        address = snap.getString("address"),
                        employeeId = snap.getString("employeeId"),
                    ),
                )
            }
        awaitClose { reg.remove() }
    }

    suspend fun changePassword(currentPassword: String, newPassword: String, forced: Boolean) {
        val user = currentUser ?: error("Not signed in")
        val email = user.email ?: error("Missing email")
        val credential = EmailAuthProvider.getCredential(email, currentPassword)
        user.reauthenticate(credential).await()
        user.updatePassword(newPassword).await()
        if (forced) {
            db.collection("users").document(user.uid)
                .update("mustChangePassword", false)
                .await()
            val token = user.getIdToken(true).await().token ?: error("Missing token")
            worker.completePasswordChange(token)
        }
    }

    suspend fun completeProfile(dob: String, address: String, phone: String) {
        val uid = currentUser?.uid ?: error("Not signed in")
        db.collection("users").document(uid).update(
            mapOf(
                "dob" to dob,
                "address" to address,
                "phone" to phone,
                "profileUpdateRequired" to false,
                "updatedAt" to DateTimeFormatter.ISO_INSTANT.format(Instant.now()),
            ),
        ).await()
    }

    suspend fun idToken(forceRefresh: Boolean = false): String {
        val user = currentUser ?: error("Not signed in")
        return user.getIdToken(forceRefresh).await().token ?: error("Missing token")
    }
}
