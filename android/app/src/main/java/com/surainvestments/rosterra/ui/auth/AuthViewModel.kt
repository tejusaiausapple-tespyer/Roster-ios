package com.surainvestments.rosterra.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.surainvestments.rosterra.core.model.AppUser
import com.surainvestments.rosterra.core.rules.BusinessRules
import com.surainvestments.rosterra.data.auth.AuthRepository
import com.surainvestments.rosterra.data.firestore.StaffRepository
import com.surainvestments.rosterra.data.prefs.SessionPrefs
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class AppRoute {
    Loading,
    Login,
    ForcedPassword,
    ProfileCompletion,
    ManagerBlocked,
    StaffMain,
}

data class AuthUiState(
    val route: AppRoute = AppRoute.Loading,
    val user: AppUser? = null,
    val email: String = "",
    val password: String = "",
    val rememberMe: Boolean = true,
    val isWorking: Boolean = false,
    val error: String? = null,
    val info: String? = null,
)

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val staffRepository: StaffRepository,
    private val prefs: SessionPrefs,
) : ViewModel() {

    private val _state = MutableStateFlow(AuthUiState())
    val state: StateFlow<AuthUiState> = combine(
        _state,
        prefs.rememberMe,
        prefs.email,
    ) { state, remember, email ->
        state.copy(
            rememberMe = remember,
            email = if (state.email.isBlank() && !email.isNullOrBlank()) email else state.email,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AuthUiState())

    init {
        viewModelScope.launch {
            authRepository.authState.collect { firebaseUser ->
                if (firebaseUser == null) {
                    staffRepository.stop()
                    _state.value = _state.value.copy(route = AppRoute.Login, user = null, isWorking = false)
                } else {
                    refreshProfile(firebaseUser.uid)
                }
            }
        }
    }

    fun onEmailChange(value: String) {
        _state.value = _state.value.copy(email = value, error = null)
    }

    fun onPasswordChange(value: String) {
        _state.value = _state.value.copy(password = value, error = null)
    }

    fun onRememberChange(value: Boolean) {
        _state.value = _state.value.copy(rememberMe = value)
    }

    fun clearMessages() {
        _state.value = _state.value.copy(error = null, info = null)
    }

    fun signIn() {
        val email = _state.value.email
        val password = _state.value.password
        if (!BusinessRules.isValidEmail(email)) {
            _state.value = _state.value.copy(error = "Enter a valid email")
            return
        }
        if (password.isBlank()) {
            _state.value = _state.value.copy(error = "Enter your password")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isWorking = true, error = null)
            runCatching {
                authRepository.signIn(email, password, _state.value.rememberMe)
            }.onSuccess { user ->
                _state.value = _state.value.copy(password = "", isWorking = false)
                applyUserRoute(user)
            }.onFailure { e ->
                _state.value = _state.value.copy(
                    isWorking = false,
                    error = e.message ?: "Sign-in failed",
                )
            }
        }
    }

    fun sendPasswordReset() {
        val email = _state.value.email
        if (!BusinessRules.isValidEmail(email)) {
            _state.value = _state.value.copy(error = "Enter your email first")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isWorking = true, error = null)
            runCatching { authRepository.sendPasswordReset(email) }
                .onSuccess {
                    _state.value = _state.value.copy(
                        isWorking = false,
                        info = "Password reset email sent",
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isWorking = false,
                        error = it.message ?: "Could not send reset email",
                    )
                }
        }
    }

    fun changePassword(current: String, newPassword: String, confirm: String) {
        val errors = BusinessRules.passwordErrors(newPassword).toMutableList()
        if (newPassword != confirm) errors += "Passwords do not match"
        if (errors.isNotEmpty()) {
            _state.value = _state.value.copy(error = errors.joinToString(" · "))
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isWorking = true, error = null)
            runCatching {
                authRepository.changePassword(current, newPassword, forced = true)
                authRepository.fetchUser()
            }.onSuccess { user ->
                _state.value = _state.value.copy(isWorking = false)
                applyUserRoute(user)
            }.onFailure {
                _state.value = _state.value.copy(
                    isWorking = false,
                    error = it.message ?: "Could not update password",
                )
            }
        }
    }

    fun completeProfile(dob: String, address: String, phone: String) {
        if (dob.isBlank() || address.isBlank() || phone.isBlank()) {
            _state.value = _state.value.copy(error = "Date of birth, address, and phone are required")
            return
        }
        viewModelScope.launch {
            _state.value = _state.value.copy(isWorking = true, error = null)
            runCatching {
                authRepository.completeProfile(dob, address, phone)
                authRepository.fetchUser()
            }.onSuccess { user ->
                _state.value = _state.value.copy(isWorking = false)
                applyUserRoute(user)
            }.onFailure {
                _state.value = _state.value.copy(
                    isWorking = false,
                    error = it.message ?: "Could not save profile",
                )
            }
        }
    }

    fun signOut() {
        viewModelScope.launch {
            staffRepository.stop()
            authRepository.signOut()
        }
    }

    private suspend fun refreshProfile(uid: String) {
        _state.value = _state.value.copy(isWorking = true, route = AppRoute.Loading)
        runCatching { authRepository.fetchUser(uid) }
            .onSuccess { applyUserRoute(it) }
            .onFailure {
                staffRepository.stop()
                authRepository.signOut()
                _state.value = _state.value.copy(
                    isWorking = false,
                    route = AppRoute.Login,
                    error = it.message ?: "Could not load profile",
                )
            }
    }

    private fun applyUserRoute(user: AppUser) {
        val route = when {
            !user.isActiveAccount -> {
                viewModelScope.launch { authRepository.signOut() }
                AppRoute.Login
            }
            user.isManager -> AppRoute.ManagerBlocked
            user.mustChangePassword -> AppRoute.ForcedPassword
            user.needsProfileCompletion -> AppRoute.ProfileCompletion
            else -> {
                staffRepository.start(user.id)
                AppRoute.StaffMain
            }
        }
        _state.value = _state.value.copy(
            user = user,
            route = route,
            isWorking = false,
            error = if (!user.isActiveAccount) "This account is ${user.status.raw}." else _state.value.error,
        )
    }
}
