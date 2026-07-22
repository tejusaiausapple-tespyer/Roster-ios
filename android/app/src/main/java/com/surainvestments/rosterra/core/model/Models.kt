package com.surainvestments.rosterra.core.model

import com.surainvestments.rosterra.core.calendar.RosterCalendar
import java.time.Instant
import java.time.ZonedDateTime

data class AppUser(
    val id: String,
    val fullName: String = "",
    val email: String = "",
    val phone: String? = null,
    val role: UserRole = UserRole.STAFF,
    val status: UserStatus = UserStatus.ACTIVE,
    val mustChangePassword: Boolean = false,
    val needsSetup: Boolean = false,
    val profileUpdateRequired: Boolean = false,
    val dob: String? = null,
    val address: String? = null,
    val employeeId: String? = null,
) {
    val firstName: String
        get() = fullName.trim().split("\\s+".toRegex()).firstOrNull().orEmpty()

    val needsProfileCompletion: Boolean
        get() = profileUpdateRequired ||
            dob.isNullOrBlank() ||
            address.isNullOrBlank() ||
            phone.isNullOrBlank()

    val isStaff: Boolean get() = role == UserRole.STAFF
    val isManager: Boolean get() = role == UserRole.MANAGER
    val isActiveAccount: Boolean get() = status == UserStatus.ACTIVE
}

data class Shift(
    val id: String,
    val staffId: String,
    val date: String,
    val rosteredStart: String,
    val rosteredEnd: String,
    val breakMinutes: Int = 0,
    val location: String? = null,
    val notes: String? = null,
    val status: ShiftStatus = ShiftStatus.PUBLISHED,
    val submittableAfterMillis: Long? = null,
) {
    val startDateTime: ZonedDateTime
        get() = RosterCalendar.zonedDateTime(date, rosteredStart)
            ?: RosterCalendar.now()

    val endDateTime: ZonedDateTime
        get() {
            val end = RosterCalendar.zonedDateTime(date, rosteredEnd) ?: return startDateTime
            return if (rosteredEnd <= rosteredStart) end.plusDays(1) else end
        }

    val submittableAfterDate: Instant
        get() = submittableAfterMillis?.let { Instant.ofEpochMilli(it) }
            ?: endDateTime.toInstant()

    fun isSubmittable(at: Instant = Instant.now()): Boolean = !at.isBefore(submittableAfterDate)
}

data class Timesheet(
    val id: String,
    val shiftId: String,
    val staffId: String,
    val actualStart: String = "",
    val actualEnd: String = "",
    val actualBreakMinutes: Int = 0,
    val workedHours: Double = 0.0,
    val staffNotes: String? = null,
    val status: TimesheetStatus = TimesheetStatus.PENDING,
    val rejectedReason: String? = null,
) {
    val isStaffReportedAbsence: Boolean get() = status == TimesheetStatus.ABSENT_REPORTED

    val isStaffEditable: Boolean
        get() = when (status) {
            TimesheetStatus.DRAFT,
            TimesheetStatus.PENDING,
            TimesheetStatus.REJECTED,
            TimesheetStatus.ABSENT_REPORTED -> true
            TimesheetStatus.APPROVED,
            TimesheetStatus.ABSENT -> false
        }
}
