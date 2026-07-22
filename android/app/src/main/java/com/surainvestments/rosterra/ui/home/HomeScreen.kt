package com.surainvestments.rosterra.ui.home

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.surainvestments.rosterra.core.calendar.RosterCalendar
import com.surainvestments.rosterra.core.model.AppUser
import com.surainvestments.rosterra.core.rules.BusinessRules

@Composable
fun HomeScreen(
    user: AppUser?,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val shifts by viewModel.shifts.collectAsStateWithLifecycle()
    val company by viewModel.companyName.collectAsStateWithLifecycle()
    val loading by viewModel.isLoading.collectAsStateWithLifecycle()
    val today = RosterCalendar.todayKey()
    val todayShifts = shifts.filter { it.date == today }
    val upcoming = shifts.filter { it.date > today }.take(5)

    LazyColumn(
        modifier = Mod.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                text = company,
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "Hi ${user?.firstName ?: "there"}",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold,
            )
        }
        item {
            Text("Today", style = MaterialTheme.typography.titleMedium)
            if (loading && todayShifts.isEmpty()) {
                CircularProgressIndicator(modifier = Mod.padding(top = 8.dp))
            } else if (todayShifts.isEmpty()) {
                Text(
                    "No shift today",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(todayShifts, key = { it.id }) { shift ->
            val ts = viewModel.timesheetFor(shift.id)
            val status = BusinessRules.displayStatus(shift, ts)
            ShiftSummaryCard(
                title = "${shift.rosteredStart} – ${shift.rosteredEnd}",
                subtitle = shift.location ?: "Shift",
                status = status.raw.replace('_', ' '),
            )
        }
        item {
            Spacer(Mod.height(4.dp))
            Text("Upcoming", style = MaterialTheme.typography.titleMedium)
            if (upcoming.isEmpty()) {
                Text(
                    "No upcoming shifts in view",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        items(upcoming, key = { it.id }) { shift ->
            ShiftSummaryCard(
                title = "${shift.date} · ${shift.rosteredStart} – ${shift.rosteredEnd}",
                subtitle = shift.location ?: "Shift",
                status = BusinessRules.displayStatus(shift, viewModel.timesheetFor(shift.id)).raw
                    .replace('_', ' '),
            )
        }
    }
}

@Composable
private fun ShiftSummaryCard(title: String, subtitle: String, status: String) {
    Card(modifier = Mod.fillMaxWidth()) {
        Column(modifier = Mod.padding(16.dp)) {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                status.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
