package com.surainvestments.rosterra.ui.auth

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp

@Composable
fun ProfileCompletionScreen(
    state: AuthUiState,
    vm: AuthViewModel,
) {
    var dob by remember { mutableStateOf(state.user?.dob.orEmpty()) }
    var address by remember { mutableStateOf(state.user?.address.orEmpty()) }
    var phone by remember { mutableStateOf(state.user?.phone.orEmpty()) }

    Column(
        modifier = Mod.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Complete your profile", style = MaterialTheme.typography.headlineSmall)
        Text(
            "We need a few details before you can use Rosterra.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Mod.height(16.dp))
        OutlinedTextField(
            value = dob,
            onValueChange = { dob = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("Date of birth (yyyy-MM-dd)") },
            singleLine = true,
        )
        Spacer(Mod.height(8.dp))
        OutlinedTextField(
            value = address,
            onValueChange = { address = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("Address") },
            singleLine = true,
        )
        Spacer(Mod.height(8.dp))
        OutlinedTextField(
            value = phone,
            onValueChange = { phone = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("Phone") },
            singleLine = true,
        )
        state.error?.let {
            Spacer(Mod.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Mod.height(16.dp))
        Button(
            onClick = { vm.completeProfile(dob.trim(), address.trim(), phone.trim()) },
            enabled = !state.isWorking,
            modifier = Mod.fillMaxWidth(),
        ) { Text("Save and continue") }
        TextButton(onClick = vm::signOut) { Text("Sign out") }
    }
}
