package com.surainvestments.rosterra.ui.availability

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
import com.surainvestments.rosterra.core.calendar.RosterCalendar
import com.surainvestments.rosterra.core.rules.BusinessRules

@Composable
fun AvailabilityScreen() {
    val week = RosterCalendar.weekStartKey()
    val locked = BusinessRules.isWeekLockedForStaff(week)
    Column(
        modifier = Mod.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text("Availability", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
        Text("Current week: $week")
        Text(
            if (locked) "This week is locked for edits (past/current weeks)."
            else "This week is editable.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            "Full day editor + Worker save lands in milestone A5.",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
