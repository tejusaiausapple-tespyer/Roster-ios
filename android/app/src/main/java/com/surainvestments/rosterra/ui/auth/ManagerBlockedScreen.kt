package com.surainvestments.rosterra.ui.auth

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

@Composable
fun ManagerBlockedScreen(
    userName: String,
    onSignOut: () -> Unit,
) {
    Column(
        modifier = Mod.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Manager accounts", style = MaterialTheme.typography.headlineSmall)
        Spacer(Mod.height(8.dp))
        Text(
            if (userName.isBlank()) {
                "This Android app is Staff-only for now. Managers should use the iOS app or web portal."
            } else {
                "Hi $userName — this Android app is Staff-only for now. Managers should use the iOS app or web portal."
            },
            style = MaterialTheme.typography.bodyLarge,
        )
        Spacer(Mod.height(24.dp))
        Button(onClick = onSignOut) { Text("Sign out") }
    }
}
