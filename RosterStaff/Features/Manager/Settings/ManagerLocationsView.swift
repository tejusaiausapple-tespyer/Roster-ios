import SwiftUI

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

    init(mode: ManagerLocationsView.EditorMode, onSave: @escaping (RosterLocation) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _suburb = State(initialValue: "")
            _state = State(initialValue: "SA")
            _city = State(initialValue: RosterLocation.capital(for: "SA"))
        case .edit(let location):
            _suburb = State(initialValue: location.suburb)
            _state = State(initialValue: location.state)
            _city = State(initialValue: location.city)
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
                                              city: trimmedCity.isEmpty ? nil : trimmedCity))
                        dismiss()
                    }
                    .disabled(suburb.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
