package com.surainvestments.rosterra.data.firestore

import com.google.firebase.Timestamp
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.surainvestments.rosterra.core.model.Shift
import com.surainvestments.rosterra.core.model.ShiftStatus
import com.surainvestments.rosterra.core.model.Timesheet
import com.surainvestments.rosterra.core.model.TimesheetStatus
import com.surainvestments.rosterra.core.rules.BusinessRules
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Staff-scoped live data. Manager/all-staff queries are intentionally absent.
 */
@Singleton
class StaffRepository @Inject constructor() {
    private val db: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    private val _shifts = MutableStateFlow<List<Shift>>(emptyList())
    val shifts: StateFlow<List<Shift>> = _shifts.asStateFlow()

    private val _timesheets = MutableStateFlow<List<Timesheet>>(emptyList())
    val timesheets: StateFlow<List<Timesheet>> = _timesheets.asStateFlow()

    private val _companyName = MutableStateFlow("Rosterra")
    val companyName: StateFlow<String> = _companyName.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val regs = mutableListOf<ListenerRegistration>()
    private var activeUid: String? = null

    fun start(uid: String) {
        if (activeUid == uid && regs.isNotEmpty()) return
        stop()
        activeUid = uid
        _isLoading.value = true
        val (start, end) = BusinessRules.staffShiftDateRange()

        regs += db.collection("shifts")
            .whereEqualTo("staffId", uid)
            .whereEqualTo("status", "published")
            .whereGreaterThanOrEqualTo("date", start)
            .whereLessThanOrEqualTo("date", end)
            .addSnapshotListener { snap, _ ->
                _shifts.value = snap?.documents?.mapNotNull { doc ->
                    Shift(
                        id = doc.id,
                        staffId = doc.getString("staffId").orEmpty(),
                        date = doc.getString("date").orEmpty(),
                        rosteredStart = doc.getString("rosteredStart").orEmpty(),
                        rosteredEnd = doc.getString("rosteredEnd").orEmpty(),
                        breakMinutes = (doc.getLong("breakMinutes") ?: 0L).toInt(),
                        location = doc.getString("location"),
                        notes = doc.getString("notes"),
                        status = ShiftStatus.fromRaw(doc.getString("status")),
                        submittableAfterMillis = (doc.get("submittableAfter") as? Timestamp)
                            ?.toDate()?.time,
                    )
                }?.sortedBy { it.date + it.rosteredStart }.orEmpty()
                _isLoading.value = false
            }

        regs += db.collection("timesheets")
            .whereEqualTo("staffId", uid)
            .addSnapshotListener { snap, _ ->
                _timesheets.value = snap?.documents?.mapNotNull { doc ->
                    Timesheet(
                        id = doc.id,
                        shiftId = doc.getString("shiftId") ?: doc.id,
                        staffId = doc.getString("staffId").orEmpty(),
                        actualStart = doc.getString("actualStart").orEmpty(),
                        actualEnd = doc.getString("actualEnd").orEmpty(),
                        actualBreakMinutes = (doc.getLong("actualBreakMinutes") ?: 0L).toInt(),
                        workedHours = doc.getDouble("workedHours") ?: 0.0,
                        staffNotes = doc.getString("staffNotes"),
                        status = TimesheetStatus.fromRaw(doc.getString("status")),
                        rejectedReason = doc.getString("rejectedReason"),
                    )
                }.orEmpty()
            }

        regs += db.collection("settings").document("app")
            .addSnapshotListener { snap, _ ->
                _companyName.value = snap?.getString("companyName") ?: "Rosterra"
            }
    }

    fun stop() {
        regs.forEach { it.remove() }
        regs.clear()
        activeUid = null
        _shifts.value = emptyList()
        _timesheets.value = emptyList()
        _isLoading.value = false
    }

    fun timesheetFor(shiftId: String): Timesheet? =
        _timesheets.value.firstOrNull { it.shiftId == shiftId || it.id == shiftId }
}
