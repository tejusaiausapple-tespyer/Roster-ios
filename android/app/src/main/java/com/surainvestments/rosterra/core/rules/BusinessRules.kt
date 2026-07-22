package com.surainvestments.rosterra.core.rules

import com.surainvestments.rosterra.core.calendar.RosterCalendar
import com.surainvestments.rosterra.core.model.Shift
import com.surainvestments.rosterra.core.model.ShiftStatus
import com.surainvestments.rosterra.core.model.StaffShiftDisplayStatus
import com.surainvestments.rosterra.core.model.Timesheet
import com.surainvestments.rosterra.core.model.TimesheetStatus
import java.time.Instant
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import kotlin.math.max
import kotlin.math.round

/**
 * Staff-facing business rules — 1:1 port of iOS `BusinessRules`.
 * Manager-only helpers are intentionally omitted from the Staff app.
 */
object BusinessRules {
    const val BREAK_MINUTES_MIN = 0
    const val BREAK_MINUTES_MAX = 90
    const val BREAK_MINUTES_STEP = 5
    const val SHIFT_WINDOW_DAYS_BACK = 28
    const val SHIFT_WINDOW_DAYS_FORWARD = 56
    const val AVAILABILITY_MAX_WEEK_OFFSET = 12
    const val AVAILABILITY_MIN_WEEK_OFFSET = -2
    const val DEFAULT_SUPER_RATE_PERCENT = 12.0

    fun shiftStartDateTime(date: String, time: String): ZonedDateTime =
        RosterCalendar.zonedDateTime(date, time) ?: RosterCalendar.now()

    fun shiftEndDateTime(date: String, start: String, end: String): ZonedDateTime {
        var endDate = shiftStartDateTime(date, end)
        if (end <= start) endDate = endDate.plusDays(1)
        return endDate
    }

    fun calcWorkedHours(start: String, end: String, breakMinutes: Int): Double {
        val s = start.split(":").mapNotNull { it.toIntOrNull() }
        val e = end.split(":").mapNotNull { it.toIntOrNull() }
        if (s.size < 2 || e.size < 2) return 0.0
        val startMins = s[0] * 60 + s[1]
        var endMins = e[0] * 60 + e[1]
        if (endMins < startMins) endMins += 24 * 60
        val total = endMins - startMins - breakMinutes
        val hours = max(0, total).toDouble() / 60.0
        return round(hours * 100.0) / 100.0
    }

    fun clampBreakMinutes(value: Int): Int =
        value.coerceIn(BREAK_MINUTES_MIN, BREAK_MINUTES_MAX)

    fun staffShiftDateRange(at: ZonedDateTime = RosterCalendar.now()): Pair<String, String> {
        val start = at.toLocalDate().minusDays(SHIFT_WINDOW_DAYS_BACK.toLong())
        val end = at.toLocalDate().plusDays(SHIFT_WINDOW_DAYS_FORWARD.toLong())
        return RosterCalendar.dayKey(start) to RosterCalendar.dayKey(end)
    }

    fun staffTimesheetCutoff(at: ZonedDateTime = RosterCalendar.now()): Instant =
        at.minusDays(365L * 5).toInstant()

    fun isWeekLockedForStaff(
        weekStartKey: String,
        at: ZonedDateTime = RosterCalendar.now(),
    ): Boolean = weekStartKey <= RosterCalendar.weekStartKey(at.toLocalDate())

    fun isWeekLockedForStaff(
        weekStartKey: String,
        managerLockedWeeks: Set<String>,
        at: ZonedDateTime = RosterCalendar.now(),
    ): Boolean = isWeekLockedForStaff(weekStartKey, at) || weekStartKey in managerLockedWeeks

    fun recurringWeekKeys(fromMonday: LocalDate, at: ZonedDateTime = RosterCalendar.now()): List<String> {
        val horizon = RosterCalendar.weekStart(at.toLocalDate())
            .plusWeeks(AVAILABILITY_MAX_WEEK_OFFSET.toLong())
        var monday = RosterCalendar.weekStart(fromMonday)
        val keys = mutableListOf<String>()
        while (!monday.isAfter(horizon)) {
            keys += RosterCalendar.dayKey(monday)
            monday = monday.plusWeeks(1)
        }
        return keys
    }

    fun displayStatus(
        shift: Shift,
        timesheet: Timesheet?,
        at: Instant = Instant.now(),
    ): StaffShiftDisplayStatus {
        if (timesheet != null) {
            return StaffShiftDisplayStatus.fromRaw(timesheet.status.raw)
                ?: StaffShiftDisplayStatus.PENDING
        }
        return if (shift.isSubmittable(at)) {
            StaffShiftDisplayStatus.AWAITING_SUBMISSION
        } else {
            StaffShiftDisplayStatus.SCHEDULED
        }
    }

    fun needsStaffAction(
        shift: Shift,
        timesheet: Timesheet?,
        at: Instant = Instant.now(),
    ): Boolean {
        if (timesheet == null && shift.isSubmittable(at)) return true
        if (timesheet?.status == TimesheetStatus.REJECTED) return true
        if (timesheet?.isStaffReportedAbsence == true) return true
        return false
    }

    fun canReportAbsence(
        shift: Shift,
        timesheet: Timesheet?,
        at: Instant = Instant.now(),
    ): Boolean {
        if (!shift.isSubmittable(at)) return false
        if (timesheet == null) return true
        return timesheet.status == TimesheetStatus.REJECTED
    }

    fun canSubmitHours(
        shift: Shift,
        timesheet: Timesheet?,
        at: Instant = Instant.now(),
    ): Boolean {
        if (shift.status != ShiftStatus.PUBLISHED || !shift.isSubmittable(at)) return false
        if (timesheet == null) return true
        return timesheet.status == TimesheetStatus.REJECTED ||
            timesheet.status == TimesheetStatus.PENDING ||
            timesheet.status == TimesheetStatus.DRAFT
    }

    fun isValidEmail(email: String): Boolean {
        val trimmed = email.trim()
        return Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").containsMatchIn(trimmed)
    }

    fun passwordErrors(password: String): List<String> {
        val errors = mutableListOf<String>()
        if (password.length < 8) errors += "At least 8 characters"
        if (!password.contains(Regex("[A-Z]"))) errors += "One uppercase letter"
        if (!password.contains(Regex("[0-9]"))) errors += "One number"
        return errors
    }

    data class PasswordRule(
        val label: String,
        val isMet: Boolean,
        val required: Boolean,
    )

    fun passwordRules(password: String): List<PasswordRule> = listOf(
        PasswordRule("At least 8 characters", password.length >= 8, true),
        PasswordRule("One uppercase letter", password.contains(Regex("[A-Z]")), true),
        PasswordRule("One number", password.contains(Regex("[0-9]")), true),
        PasswordRule("One symbol (recommended)", password.contains(Regex("[^A-Za-z0-9]")), false),
    )

    fun shiftWeekOffsetBounds(at: ZonedDateTime = RosterCalendar.now()): Pair<Int, Int> {
        val (startKey, endKey) = staffShiftDateRange(at)
        val todayMonday = RosterCalendar.weekStart(at.toLocalDate())
        val startDate = RosterCalendar.dateFromKey(startKey) ?: return -4 to 8
        val endDate = RosterCalendar.dateFromKey(endKey) ?: return -4 to 8
        val startMonday = RosterCalendar.weekStart(startDate)
        val endMonday = RosterCalendar.weekStart(endDate)
        val minWeeks = ChronoUnit.WEEKS.between(todayMonday, startMonday).toInt()
        val maxWeeks = ChronoUnit.WEEKS.between(todayMonday, endMonday).toInt()
        return minWeeks to maxWeeks
    }
}
