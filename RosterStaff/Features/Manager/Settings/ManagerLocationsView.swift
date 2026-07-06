import SwiftUI
import MapKit

/// Account → Locations: manage the saved work locations offered as a dropdown
/// wherever a location is required (shift editor today; rosters/reports later).
/// Edits/deletes only change the saved list — shifts keep the location string
/// they were created with.
struct ManagerLocationsView: View {
    @Environment(RosterRepository.self) private var repo

    @State private var editor: EditorMode?
    @State private var toast: ToastMessage?
    @State private var isWorking = false

    enum EditorMode: Identifiable {
        case add
        case edit(RosterLocation)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let location): return "edit-\(location.id)"
            }
        }
    }

    var body: some View {
        List {
            if repo.locations.isEmpty {
                Section {
                    Text("No locations yet. Add the suburbs your staff work in — they'll appear as a dropdown when creating shifts.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Section {
                    ForEach(repo.locations) { location in
                        Button {
                            editor = .edit(location)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.displayName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(location.city)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "pencil")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Swipe left to delete. Deleting or editing a location doesn't change shifts already created with it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Locations", icon: "mappin.and.ellipse")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add location")
            }
        }
        .sheet(item: $editor) { mode in
            LocationEditorSheet(mode: mode) { newLocation in
                Task { await save(mode: mode, newLocation: newLocation) }
            }
        }
        .toast($toast)
        .disabled(isWorking)
    }

    private func save(mode: EditorMode, newLocation: RosterLocation) async {
        isWorking = true
        defer { isWorking = false }
        do {
            switch mode {
            case .add:
                try await repo.addLocation(newLocation)
            case .edit(let old):
                var updated = repo.locations.filter { $0 != old }
                updated.append(newLocation)
                try await repo.setLocations(updated)
            }
            Haptics.success()
        } catch {
            toast = ToastMessage(kind: .error, text: "Couldn't save. \(error.localizedDescription)")
            Haptics.error()
        }
    }

    private func delete(at offsets: IndexSet) {
        let remaining = repo.locations.enumerated()
            .filter { !offsets.contains($0.offset) }
            .map { $0.element }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await repo.setLocations(remaining)
                Haptics.light()
            } catch {
                toast = ToastMessage(kind: .error, text: "Couldn't delete. \(error.localizedDescription)")
                Haptics.error()
            }
        }
    }
}

/// Add/edit form: suburb + state (capital city auto-fills, editable).
private struct LocationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: ManagerLocationsView.EditorMode
    let onSave: (RosterLocation) -> Void

    @State private var suburb: String
    @State private var state: String
    @State private var city: String
    @State private var geofenceAddress = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var geofenceRadius: Double
    @State private var geofenceEnforced: Bool
    @State private var isGeocoding = false
    @State private var isLocating = false
    @State private var geocodeError: String?

    init(mode: ManagerLocationsView.EditorMode, onSave: @escaping (RosterLocation) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _suburb = State(initialValue: "")
            _state = State(initialValue: "SA")
            _city = State(initialValue: RosterLocation.capital(for: "SA"))
            _latitude = State(initialValue: nil)
            _longitude = State(initialValue: nil)
            _geofenceRadius = State(initialValue: RosterLocation.defaultGeofenceRadius)
            _geofenceEnforced = State(initialValue: false)
        case .edit(let location):
            _suburb = State(initialValue: location.suburb)
            _state = State(initialValue: location.state)
            _city = State(initialValue: location.city)
            _latitude = State(initialValue: location.latitude)
            _longitude = State(initialValue: location.longitude)
            // Snap legacy radii (e.g. 500 m / 1 km from earlier options) to
            // the nearest current choice so the picker always has a selection.
            let options = [50.0, 75.0, 100.0, 250.0]
            let saved = location.effectiveGeofenceRadius
            _geofenceRadius = State(initialValue: options.min {
                abs($0 - saved) < abs($1 - saved)
            } ?? RosterLocation.defaultGeofenceRadius)
            _geofenceEnforced = State(initialValue: location.geofenceEnforced)
        }
    }

    private var isEdit: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Suburb", text: $suburb)
                        .textInputAutocapitalization(.words)
                    Picker("State", selection: $state) {
                        ForEach(RosterLocation.states, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: state) { _, newValue in
                        city = RosterLocation.capital(for: newValue)
                    }
                    TextField("City", text: $city)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("The city fills in automatically from the state's capital — change it if the location is elsewhere.")
                }

                Section {
                    if let latitude, let longitude {
                        HStack {
                            Label("Geofence set", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                self.latitude = nil
                                self.longitude = nil
                            }
                            .font(.subheadline)
                        }

                        // Interactive map: tap anywhere to move the anchor pin;
                        // the circle previews the allowed clock-in area live.
                        GeofenceMapEditor(
                            coordinate: Binding(
                                get: { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) },
                                set: { self.latitude = $0.latitude; self.longitude = $0.longitude }
                            ),
                            radius: geofenceRadius
                        )
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())

                        Text(String(format: "%.5f, %.5f", latitude, longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                        Picker("Allowed radius", selection: $geofenceRadius) {
                            ForEach([50.0, 75.0, 100.0, 250.0], id: \.self) { r in
                                Text("\(Int(r)) m").tag(r)
                            }
                        }
                        Toggle("Enforce geofence", isOn: $geofenceEnforced)
                        Text(geofenceEnforced
                             ? "Staff outside the radius are blocked from starting a shift here."
                             : "Starts are allowed within 250 m; further out, staff are warned and the attempt is recorded. Ending a shift is never restricted.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        TextField("Workplace address", text: $geofenceAddress)
                            .textInputAutocapitalization(.words)
                        Button {
                            Task { await geocode() }
                        } label: {
                            if isGeocoding {
                                ProgressView()
                            } else {
                                Label("Find coordinates", systemImage: "location.magnifyingglass")
                            }
                        }
                        .disabled(isGeocoding || geofenceAddress.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button {
                            Task { await useCurrentLocation() }
                        } label: {
                            if isLocating {
                                ProgressView()
                            } else {
                                Label("Use my current location", systemImage: "location.fill")
                            }
                        }
                        .disabled(isLocating)
                        if let geocodeError {
                            Text(geocodeError)
                                .font(.caption)
                                .foregroundStyle(Theme.error)
                        }
                    }
                } header: {
                    Text("Attendance geofence")
                } footer: {
                    Text(latitude != nil
                         ? "Tap the map to move the pin to the exact workplace entrance. The circle shows where staff can clock in and out."
                         : "With a geofence set, staff starting or ending a shift here have their GPS position checked against this point. Without one, attendance is recorded but not verified.")
                }
            }
            .navigationTitle(isEdit ? "Edit Location" : "New Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = suburb.trimmingCharacters(in: .whitespaces)
                        let trimmedCity = city.trimmingCharacters(in: .whitespaces)
                        onSave(RosterLocation(suburb: trimmed, state: state,
                                              city: trimmedCity.isEmpty ? nil : trimmedCity,
                                              latitude: latitude, longitude: longitude,
                                              geofenceRadius: latitude != nil ? geofenceRadius : nil,
                                              geofenceEnforced: latitude != nil && geofenceEnforced))
                        dismiss()
                    }
                    .disabled(suburb.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Resolve the typed address to coordinates with MKLocalSearch.
    private func geocode() async {
        isGeocoding = true
        geocodeError = nil
        defer { isGeocoding = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(geofenceAddress), \(suburb) \(state), Australia"
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else {
                geocodeError = "No match found. Try a fuller address."
                return
            }
            latitude = item.placemark.coordinate.latitude
            longitude = item.placemark.coordinate.longitude
            Haptics.success()
        } catch {
            geocodeError = "Address lookup failed. Check your connection and try again."
        }
    }

    /// Drop the pin at the manager's current position (they're usually
    /// standing at the workplace when setting this up).
    private func useCurrentLocation() async {
        isLocating = true
        geocodeError = nil
        defer { isLocating = false }
        do {
            let location = try await LocationService.shared.currentLocation()
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
            Haptics.success()
        } catch {
            geocodeError = (error as? LocalizedError)?.errorDescription ?? "Couldn't get your location."
        }
    }
}

/// Interactive geofence editor: pin at the anchor, translucent circle for the
/// allowed radius, tap anywhere on the map to move the pin there.
private struct GeofenceMapEditor: View {
    @Binding var coordinate: CLLocationCoordinate2D
    let radius: Double

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                Annotation("Workplace", coordinate: coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, Theme.brand)
                        .shadow(radius: 2)
                }
                MapCircle(center: coordinate, radius: radius)
                    .foregroundStyle(Theme.brand.opacity(0.15))
                    .stroke(Theme.brand.opacity(0.6), lineWidth: 2)
            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .onTapGesture { screenPoint in
                if let tapped = proxy.convert(screenPoint, from: .local) {
                    coordinate = tapped
                    Haptics.selection()
                }
            }
        }
        .onAppear { recenter() }
        .onChange(of: radius) { recenter() }
        .onChange(of: coordinate.latitude) { recenter() }
        .onChange(of: coordinate.longitude) { recenter() }
    }

    /// Keep the whole circle in view with some margin.
    private func recenter() {
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: radius * 3.2,
                longitudinalMeters: radius * 3.2
            ))
        }
    }
}
