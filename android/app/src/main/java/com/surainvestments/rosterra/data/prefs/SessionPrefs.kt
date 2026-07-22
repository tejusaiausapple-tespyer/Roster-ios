package com.surainvestments.rosterra.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class SessionPrefs @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val store = PreferenceDataStoreFactory.create(
        produceFile = { context.preferencesDataStoreFile("rosterra_session") },
    )

    private val rememberEmail = booleanPreferencesKey("remember_email")
    private val savedEmail = stringPreferencesKey("saved_email")
    private val lastManualLogin = longPreferencesKey("last_manual_login")
    private val deviceAuthEnabled = booleanPreferencesKey("device_auth_enabled")
    private val deviceAuthVerified = booleanPreferencesKey("device_auth_verified")

    val rememberMe: Flow<Boolean> = store.data.map { it[rememberEmail] == true }
    val email: Flow<String?> = store.data.map { it[savedEmail] }
    val lastManualLoginAt: Flow<Long?> = store.data.map { it[lastManualLogin] }
    val isDeviceAuthEnabled: Flow<Boolean> = store.data.map { it[deviceAuthEnabled] == true }
    val isDeviceAuthVerified: Flow<Boolean> = store.data.map { it[deviceAuthVerified] == true }

    suspend fun setRememberedEmail(emailValue: String?, remember: Boolean) {
        store.edit {
            it[rememberEmail] = remember
            if (remember && !emailValue.isNullOrBlank()) it[savedEmail] = emailValue
            if (!remember) it.remove(savedEmail)
        }
    }

    suspend fun markManualLogin() {
        store.edit { it[lastManualLogin] = System.currentTimeMillis() }
    }

    suspend fun setDeviceAuthEnabled(enabled: Boolean) {
        store.edit { it[deviceAuthEnabled] = enabled }
    }

    suspend fun setDeviceAuthVerified(verified: Boolean) {
        store.edit { it[deviceAuthVerified] = verified }
    }

    suspend fun clearSessionFlags() {
        store.edit {
            it[deviceAuthVerified] = false
        }
    }
}
