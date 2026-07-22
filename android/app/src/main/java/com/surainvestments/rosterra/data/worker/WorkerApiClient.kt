package com.surainvestments.rosterra.data.worker

import com.surainvestments.rosterra.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

@Singleton
class WorkerApiClient @Inject constructor() {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val json = "application/json; charset=utf-8".toMediaType()

    suspend fun completePasswordChange(idToken: String) {
        post("/api/complete-password-change", idToken, JSONObject())
    }

    suspend fun requestAccountDeletion(idToken: String) {
        post(
            "/api/account-deletion/request",
            idToken,
            JSONObject().put("via", "android"),
        )
    }

    suspend fun saveAvailability(idToken: String, userId: String, weeklyAvailability: JSONObject) {
        post(
            "/api/staff/availability",
            idToken,
            JSONObject()
                .put("userId", userId)
                .put("weeklyAvailability", weeklyAvailability),
        )
    }

    suspend fun sendNotification(idToken: String, payload: JSONObject) {
        runCatching { post("/api/send-notification", idToken, payload) }
    }

    private suspend fun post(path: String, idToken: String, body: JSONObject) = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(BuildConfig.API_BASE_URL + path)
            .addHeader("Authorization", "Bearer $idToken")
            .addHeader("Content-Type", "application/json")
            .post(body.toString().toRequestBody(json))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                val err = response.body?.string().orEmpty()
                throw IllegalStateException("Worker ${response.code}: $err")
            }
        }
    }
}
