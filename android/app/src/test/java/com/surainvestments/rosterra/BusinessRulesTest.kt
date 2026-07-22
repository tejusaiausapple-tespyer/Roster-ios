package com.surainvestments.rosterra

import com.google.common.truth.Truth.assertThat
import com.surainvestments.rosterra.core.calendar.RosterCalendar
import com.surainvestments.rosterra.core.model.Shift
import com.surainvestments.rosterra.core.model.ShiftStatus
import com.surainvestments.rosterra.core.model.Timesheet
import com.surainvestments.rosterra.core.model.TimesheetStatus
import com.surainvestments.rosterra.core.rules.BusinessRules
import java.time.DayOfWeek
import java.time.Instant
import org.junit.Test

class BusinessRulesTest {
    @Test
    fun weekStartsOnMondayAdelaide() {
        val sunday = RosterCalendar.dateFromKey("2026-07-19")!! // Sunday
        assertThat(RosterCalendar.weekStart(sunday).dayOfWeek).isEqualTo(DayOfWeek.MONDAY)
        assertThat(RosterCalendar.weekStartKey(sunday)).isEqualTo("2026-07-13")
    }

    @Test
    fun calcWorkedHoursCrossesMidnight() {
        val hours = BusinessRules.calcWorkedHours("22:00", "02:00", 30)
        assertThat(hours).isEqualTo(3.5)
    }

    @Test
    fun passwordErrorsRequireUppercaseNumberAndLength() {
        assertThat(BusinessRules.passwordErrors("short")).isNotEmpty()
        assertThat(BusinessRules.passwordErrors("longenough1")).contains("One uppercase letter")
        assertThat(BusinessRules.passwordErrors("Longenough")).contains("One number")
        assertThat(BusinessRules.passwordErrors("Longenough1")).isEmpty()
    }

    @Test
    fun canSubmitHoursWhenPublishedAndSubmittable() {
        val shift = Shift(
            id = "s1",
            staffId = "u1",
            date = "2026-07-01",
            rosteredStart = "09:00",
            rosteredEnd = "17:00",
            status = ShiftStatus.PUBLISHED,
            submittableAfterMillis = Instant.parse("2026-07-01T07:30:00Z").toEpochMilli(),
        )
        val at = Instant.parse("2026-07-01T08:00:00Z")
        assertThat(BusinessRules.canSubmitHours(shift, null, at)).isTrue()
        val pending = Timesheet("s1", "s1", "u1", status = TimesheetStatus.PENDING)
        assertThat(BusinessRules.canSubmitHours(shift, pending, at)).isTrue()
        val approved = pending.copy(status = TimesheetStatus.APPROVED)
        assertThat(BusinessRules.canSubmitHours(shift, approved, at)).isFalse()
    }

    @Test
    fun currentWeekIsLockedForAvailability() {
        val week = RosterCalendar.weekStartKey()
        assertThat(BusinessRules.isWeekLockedForStaff(week)).isTrue()
    }
}
