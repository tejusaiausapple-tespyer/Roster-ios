package com.surainvestments.rosterra.ui.auth

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

@Composable
fun LoginScreen(
    state: AuthUiState,
    onEvent: AuthViewModel,
) {
    Column(
        modifier = Mod
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = "Rosterra",
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary,
        )
        Text(
            text = "Staff sign in",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Mod.height(24.dp))
        OutlinedTextField(
            value = state.email,
            onValueChange = onEvent::onEmailChange,
            modifier = Mod.fillMaxWidth(),
            label = { Text("Email") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
        )
        Spacer(Mod.height(12.dp))
        OutlinedTextField(
            value = state.password,
            onValueChange = onEvent::onPasswordChange,
            modifier = Mod.fillMaxWidth(),
            label = { Text("Password") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        )
        Spacer(Mod.height(8.dp))
        androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
            Checkbox(checked = state.rememberMe, onCheckedChange = onEvent::onRememberChange)
            Text("Remember me")
        }
        state.error?.let {
            Spacer(Mod.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error)
        }
        state.info?.let {
            Spacer(Mod.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.secondary)
        }
        Spacer(Mod.height(16.dp))
        Button(
            onClick = onEvent::signIn,
            enabled = !state.isWorking,
            modifier = Mod.fillMaxWidth(),
        ) {
            if (state.isWorking) CircularProgressIndicator(
                modifier = Mod.height(18.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.onPrimary,
            ) else Text("Sign in")
        }
        TextButton(onClick = onEvent::sendPasswordReset, enabled = !state.isWorking) {
            Text("Forgot password?")
        }
    }
}
