package com.surainvestments.rosterra.ui.roster

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.surainvestments.rosterra.core.calendar.RosterCalendar
import com.surainvestments.rosterra.core.rules.BusinessRules
import com.surainvestments.rosterra.ui.home.HomeViewModel

@Composable
fun RosterScreen(
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val shifts by viewModel.shifts.collectAsStateWithLifecycle()
    val weekStart = RosterCalendar.weekStartKey()
    val weekDays = RosterCalendar.weekDays(RosterCalendar.now().toLocalDate())

    LazyColumn(
        modifier = Mod.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Text("Roster", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold)
            Text(
                "Week of $weekStart",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "Submit hours, absence, history, and clock actions land in A3–A4.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        weekDays.forEach { day ->
            val key = RosterCalendar.dayKey(day)
            val dayShifts = shifts.filter { it.date == key }
            item(key = "header-$key") {
                Text(
                    key,
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Mod.padding(top = 8.dp),
                )
            }
            if (dayShifts.isEmpty()) {
                item(key = "empty-$key") {
                    Text("No shift", color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            } else {
                items(dayShifts, key = { it.id }) { shift ->
                    val ts = viewModel.timesheetFor(shift.id)
                    Card(modifier = Mod.fillMaxWidth()) {
                        Column(modifier = Mod.padding(14.dp)) {
                            Text(
                                "${shift.rosteredStart} – ${shift.rosteredEnd}",
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(shift.location ?: "Shift")
                            Text(
                                BusinessRules.displayStatus(shift, ts).raw.replace('_', ' '),
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.labelMedium,
                            )
                        }
                    }
                }
            }
        }
    }
}
