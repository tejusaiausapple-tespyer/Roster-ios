package com.surainvestments.rosterra.core.model

enum class UserRole(val raw: String) {
    STAFF("staff"),
    MANAGER("manager");

    companion object {
        fun fromRaw(value: String?): UserRole =
            entries.firstOrNull { it.raw.equals(value, ignoreCase = true) } ?: STAFF
    }
}

enum class UserStatus(val raw: String) {
    ACTIVE("active"),
    INACTIVE("inactive"),
    LOCKED("locked");

    companion object {
        fun fromRaw(value: String?): UserStatus =
            entries.firstOrNull { it.raw.equals(value, ignoreCase = true) } ?: ACTIVE
    }
}

enum class ShiftStatus(val raw: String) {
    DRAFT("draft"),
    PUBLISHED("published"),
    CANCELLED("cancelled");

    companion object {
        fun fromRaw(value: String?): ShiftStatus =
            entries.firstOrNull { it.raw.equals(value, ignoreCase = true) } ?: DRAFT
    }
}

enum class TimesheetStatus(val raw: String) {
    DRAFT("draft"),
    PENDING("pending"),
    APPROVED("approved"),
    REJECTED("rejected"),
    ABSENT_REPORTED("absent_reported"),
    ABSENT("absent");

    companion object {
        fun fromRaw(value: String?): TimesheetStatus =
            entries.firstOrNull { it.raw.equals(value, ignoreCase = true) } ?: DRAFT
    }
}

enum class StaffShiftDisplayStatus(val raw: String) {
    SCHEDULED("scheduled"),
    AWAITING_SUBMISSION("awaiting_submission"),
    DRAFT("draft"),
    PENDING("pending"),
    APPROVED("approved"),
    REJECTED("rejected"),
    ABSENT_REPORTED("absent_reported"),
    ABSENT("absent");

    companion object {
        fun fromRaw(value: String?): StaffShiftDisplayStatus? =
            entries.firstOrNull { it.raw.equals(value, ignoreCase = true) }
    }
}
