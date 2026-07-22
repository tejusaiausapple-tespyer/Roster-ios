package com.surainvestments.rosterra.ui.home

import androidx.lifecycle.ViewModel
import com.surainvestments.rosterra.core.model.Timesheet
import com.surainvestments.rosterra.data.firestore.StaffRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val staffRepository: StaffRepository,
) : ViewModel() {
    val shifts = staffRepository.shifts
    val companyName = staffRepository.companyName
    val isLoading = staffRepository.isLoading

    fun timesheetFor(shiftId: String): Timesheet? = staffRepository.timesheetFor(shiftId)
}
