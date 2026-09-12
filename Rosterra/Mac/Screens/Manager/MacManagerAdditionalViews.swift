#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Manager Wage View

struct MacManagerWageView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Wage Awards & Rates",
            subtitle: "Modern Award configurations and penalty rates"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    MacCard(title: "Penalty Rates Configuration", icon: "percent") {
                        VStack(spacing: MacSpace.md) {
                            HStack {
                                Text("Saturday Penalty Rate").font(MacType.body)
                                Spacer()
                                Text("125% (1.25x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Sunday Penalty Rate").font(MacType.body)
                                Spacer()
                                Text("150% (1.50x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Public Holiday Rate").font(MacType.body)
                                Spacer()
                                Text("225% (2.25x)").font(MacType.monoStrong)
                            }
                            HStack {
                                Text("Daily Overtime (>10h)").font(MacType.body)
                                Spacer()
                                Text("150% first 2h, then 200%").font(MacType.monoStrong)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}

// MARK: - Mac Manager Locations View

struct MacManagerLocationsView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Work Locations & Geofences",
            subtitle: "Configured workplace locations and clock-in boundaries"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    ForEach(repo.locations) { loc in
                        MacCard(title: loc.name, icon: "mappin.and.ellipse") {
                            VStack(alignment: .leading, spacing: MacSpace.sm) {
                                Text(loc.address).font(MacType.body).foregroundStyle(MacColor.textSecondary)
                                Text("Geofence Radius: \(Int(loc.radiusMeters))m").font(MacType.caption).foregroundStyle(MacColor.textTertiary)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}

// MARK: - Mac Manager Company View

struct MacManagerCompanyView: View {
    @Environment(RosterRepository.self) private var repo

    init() {}

    var body: some View {
        MacScreen(
            title: "Company Identity & Details",
            subtitle: "Legal entity information used on official payslips and tax invoices"
        ) {
            ScrollView {
                VStack(spacing: MacSpace.xl) {
                    MacCard(title: "Entity Information", icon: "building.2.fill") {
                        VStack(alignment: .leading, spacing: MacSpace.md) {
                            HStack {
                                Text("Business Name").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.name ?? "Rosterra").font(MacType.body)
                            }
                            HStack {
                                Text("Australian Business Number (ABN)").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.abn ?? "Not configured").font(MacType.mono)
                            }
                            HStack {
                                Text("Business Address").font(MacType.bodyStrong)
                                Spacer()
                                Text(repo.companyDetails?.address ?? "Adelaide, SA").font(MacType.body)
                            }
                        }
                    }
                }
                .padding(MacSpace.xl)
            }
        }
    }
}
#endif
