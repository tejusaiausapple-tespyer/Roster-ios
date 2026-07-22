package com.surainvestments.rosterra.ui.account

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.surainvestments.rosterra.core.model.AppUser

@Composable
fun AccountScreen(
    user: AppUser?,
    onSignOut: () -> Unit,
) {
    Column(
        modifier = Mod.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("Account", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Card(modifier = Mod.fillMaxWidth()) {
            Column(modifier = Mod.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(user?.fullName ?: "Staff", fontWeight = FontWeight.SemiBold)
                Text(user?.email.orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant)
                user?.employeeId?.let { Text("Employee ID: $it") }
                Text("Role: ${user?.role?.raw ?: "staff"}")
            }
        }
        Text(
            "Payslips, biometrics, notifications, legal, and account deletion land in A7–A8.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyMedium,
        )
        Spacer(Mod.height(8.dp))
        OutlinedButton(onClick = onSignOut, modifier = Mod.fillMaxWidth()) {
            Text("Sign out")
        }
        Button(
            onClick = {},
            enabled = false,
            modifier = Mod.fillMaxWidth(),
        ) { Text("Payslips (soon)") }
    }
}
