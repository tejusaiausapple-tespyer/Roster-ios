package com.surainvestments.rosterra.core.calendar

import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters

/**
 * Port of iOS `RosterCalendar` — Australia/Adelaide, Monday-start weeks.
 */
object RosterCalendar {
    val zoneId: ZoneId = ZoneId.of("Australia/Adelaide")
    private val dayFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd")
    private val monthFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyy-MM")

    fun now(): ZonedDateTime = ZonedDateTime.now(zoneId)

    fun todayKey(now: ZonedDateTime = now()): String = dayKey(now.toLocalDate())

    fun dayKey(date: LocalDate): String = date.format(dayFormatter)

    fun dateFromKey(key: String): LocalDate? = runCatching { LocalDate.parse(key, dayFormatter) }.getOrNull()

    fun weekStart(date: LocalDate = now().toLocalDate()): LocalDate =
        date.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))

    fun weekStart(instant: Instant): LocalDate =
        weekStart(instant.atZone(zoneId).toLocalDate())

    fun weekStartKey(date: LocalDate = now().toLocalDate()): String = dayKey(weekStart(date))

    fun weekDays(forDate: LocalDate): List<LocalDate> {
        val start = weekStart(forDate)
        return (0..6).map { start.plusDays(it.toLong()) }
    }

    fun addWeeks(weeks: Int, to: LocalDate): LocalDate = to.plusWeeks(weeks.toLong())

    fun addDays(days: Int, to: LocalDate): LocalDate = to.plusDays(days.toLong())

    fun addDays(days: Int, to: ZonedDateTime): ZonedDateTime = to.plusDays(days.toLong())

    fun isWeekend(dateKey: String): Boolean {
        val date = dateFromKey(dateKey) ?: return false
        val dow = date.dayOfWeek
        return dow == DayOfWeek.SATURDAY || dow == DayOfWeek.SUNDAY
    }

    fun monthKey(date: LocalDate = now().toLocalDate()): String = date.format(monthFormatter)

    fun monthKey(year: Int, month: Int): String = "%04d-%02d".format(year, month)

    fun monthKeyComponents(key: String): Pair<Int, Int>? {
        val parts = key.split("-")
        if (parts.size != 2) return null
        val year = parts[0].toIntOrNull() ?: return null
        val month = parts[1].toIntOrNull() ?: return null
        if (month !in 1..12) return null
        return year to month
    }

    fun monthStartDate(key: String): LocalDate? {
        val (year, month) = monthKeyComponents(key) ?: return null
        return LocalDate.of(year, month, 1)
    }

    fun monthDayKeyBounds(key: String): Pair<String, String>? {
        val (year, month) = monthKeyComponents(key) ?: return null
        val next = if (month == 12) (year + 1) to 1 else year to (month + 1)
        return "${monthKey(year, month)}-01" to "${monthKey(next.first, next.second)}-01"
    }

    fun monthKey(byAdding: Int, to: String): String? {
        val start = monthStartDate(to) ?: return null
        return monthKey(start.plusMonths(byAdding.toLong()))
    }

    fun zonedDateTime(dateKey: String, timeHHmm: String): ZonedDateTime? {
        val date = dateFromKey(dateKey) ?: return null
        val parts = timeHHmm.split(":")
        if (parts.size < 2) return null
        val hour = parts[0].toIntOrNull() ?: return null
        val minute = parts[1].toIntOrNull() ?: return null
        return ZonedDateTime.of(LocalDateTime.of(date, LocalTime.of(hour, minute)), zoneId)
    }

    fun toEpochMilli(zdt: ZonedDateTime): Long = zdt.toInstant().toEpochMilli()
}
