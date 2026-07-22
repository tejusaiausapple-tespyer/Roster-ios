package com.surainvestments.rosterra.ui.staff

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.TaskAlt
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.surainvestments.rosterra.core.model.AppUser
import com.surainvestments.rosterra.ui.account.AccountScreen
import com.surainvestments.rosterra.ui.availability.AvailabilityScreen
import com.surainvestments.rosterra.ui.home.HomeScreen
import com.surainvestments.rosterra.ui.roster.RosterScreen
import com.surainvestments.rosterra.ui.tasks.TasksScreen

private enum class StaffTab(
    val route: String,
    val label: String,
    val icon: ImageVector,
) {
    Home("home", "Home", Icons.Filled.Home),
    Roster("roster", "Roster", Icons.Filled.CalendarMonth),
    Tasks("tasks", "Tasks", Icons.Filled.TaskAlt),
    Availability("availability", "Availability", Icons.Filled.Schedule),
    Account("account", "Account", Icons.Filled.Person),
}

@Composable
fun StaffScaffold(
    user: AppUser?,
    onSignOut: () -> Unit,
) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val current = backStack?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                StaffTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = current == tab.route,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = StaffTab.Home.route,
            modifier = Mod.padding(padding),
        ) {
            composable(StaffTab.Home.route) { HomeScreen(user = user) }
            composable(StaffTab.Roster.route) { RosterScreen() }
            composable(StaffTab.Tasks.route) { TasksScreen() }
            composable(StaffTab.Availability.route) { AvailabilityScreen() }
            composable(StaffTab.Account.route) {
                AccountScreen(user = user, onSignOut = onSignOut)
            }
        }
    }
}
