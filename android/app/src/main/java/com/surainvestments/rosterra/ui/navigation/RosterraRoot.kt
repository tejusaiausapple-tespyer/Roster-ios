package com.surainvestments.rosterra.ui.navigation

import com.surainvestments.rosterra.core.design.Mod
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.surainvestments.rosterra.ui.auth.AppRoute
import com.surainvestments.rosterra.ui.auth.AuthViewModel
import com.surainvestments.rosterra.ui.auth.ForcedPasswordScreen
import com.surainvestments.rosterra.ui.auth.LoginScreen
import com.surainvestments.rosterra.ui.auth.ManagerBlockedScreen
import com.surainvestments.rosterra.ui.auth.ProfileCompletionScreen
import com.surainvestments.rosterra.ui.staff.StaffScaffold

@Composable
fun RosterraRoot(
    viewModel: AuthViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    when (state.route) {
        AppRoute.Loading -> Box(Mod.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        AppRoute.Login -> LoginScreen(state = state, onEvent = viewModel)
        AppRoute.ForcedPassword -> ForcedPasswordScreen(state = state, vm = viewModel)
        AppRoute.ProfileCompletion -> ProfileCompletionScreen(state = state, vm = viewModel)
        AppRoute.ManagerBlocked -> ManagerBlockedScreen(
            userName = state.user?.fullName.orEmpty(),
            onSignOut = viewModel::signOut,
        )
        AppRoute.StaffMain -> StaffScaffold(
            user = state.user,
            onSignOut = viewModel::signOut,
        )
    }
}
