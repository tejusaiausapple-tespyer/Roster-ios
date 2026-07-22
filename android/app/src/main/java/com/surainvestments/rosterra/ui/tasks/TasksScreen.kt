package com.surainvestments.rosterra.ui.tasks

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun TasksScreen() {
    Column(
        modifier = Mod.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Tasks", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Text(
            "Assigned tasks, camera proof photos, and daily jobs land in milestone A6.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
