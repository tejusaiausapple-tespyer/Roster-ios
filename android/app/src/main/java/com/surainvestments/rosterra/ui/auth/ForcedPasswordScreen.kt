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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.surainvestments.rosterra.core.rules.BusinessRules

@Composable
fun ForcedPasswordScreen(
    state: AuthUiState,
    vm: AuthViewModel,
) {
    var current by remember { mutableStateOf("") }
    var next by remember { mutableStateOf("") }
    var confirm by remember { mutableStateOf("") }

    Column(
        modifier = Mod.fillMaxSize().padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Set a new password", style = MaterialTheme.typography.headlineSmall)
        Text(
            "For security, you must change your temporary password before continuing.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Mod.height(16.dp))
        OutlinedTextField(
            value = current,
            onValueChange = { current = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("Current password") },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
        )
        Spacer(Mod.height(8.dp))
        OutlinedTextField(
            value = next,
            onValueChange = { next = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("New password") },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
        )
        Spacer(Mod.height(8.dp))
        OutlinedTextField(
            value = confirm,
            onValueChange = { confirm = it },
            modifier = Mod.fillMaxWidth(),
            label = { Text("Confirm password") },
            visualTransformation = PasswordVisualTransformation(),
            singleLine = true,
        )
        Spacer(Mod.height(12.dp))
        BusinessRules.passwordRules(next).forEach { rule ->
            Text(
                text = (if (rule.isMet) "✓ " else "• ") + rule.label +
                    if (!rule.required) "" else "",
                color = if (rule.isMet) MaterialTheme.colorScheme.secondary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        state.error?.let {
            Spacer(Mod.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
        Spacer(Mod.height(16.dp))
        Button(
            onClick = { vm.changePassword(current, next, confirm) },
            enabled = !state.isWorking,
            modifier = Mod.fillMaxWidth(),
        ) { Text("Update password") }
        TextButton(onClick = vm::signOut) { Text("Sign out") }
    }
}
