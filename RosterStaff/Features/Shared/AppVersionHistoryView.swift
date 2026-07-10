import SwiftUI

/// Release history page — pushed from both Staff and Manager Account → About → Version.
struct AppVersionHistoryView: View {
    @State private var expandedSet: Set<String>

    init() {
        // Latest release starts expanded.
        _expandedSet = State(initialValue: [ReleaseHistory.current.version])
    }

    var body: some View {
        List {
            TitlePillCollapseReporter()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section { currentVersionHeader }

            Section("Changelog") {
                ForEach(ReleaseHistory.all) { release in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSet.contains(release.version) },
                            set: { isOpen in
                                if isOpen { expandedSet.insert(release.version) }
                                else { expandedSet.remove(release.version) }
                            }
                        )
                    ) {
                        releaseDetail(release)
                    } label: {
                        releaseRow(release)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Version")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Version", icon: "info.circle.fill")
            }
        }
    }

    // MARK: - Current Version Header

    private var currentVersionHeader: some View {
        let r = ReleaseHistory.current
        return VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                    .fill(Theme.brand.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.brand)
            }
            VStack(spacing: 4) {
                Text("Rosterra")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 8) {
                    Text("v\(r.version)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    typeBadge(r.updateType)
                }
                Text("Build \(r.build)  ·  \(r.formattedReleaseDate)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Release Row (DisclosureGroup Label)

    private func releaseRow(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("v\(release.version)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                typeBadge(release.updateType)
                if release.version == ReleaseHistory.current.version {
                    Text("Current")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                }
                Spacer()
            }
            Text(release.formattedReleaseDate)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            if !release.summary.isEmpty {
                Text(release.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(expandedSet.contains(release.version) ? nil : 2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Release Detail (DisclosureGroup Content)

    @ViewBuilder
    private func releaseDetail(_ release: AppRelease) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if !release.features.isEmpty {
                bulletSection(
                    title: "What's New",
                    icon: "sparkles",
                    items: release.features,
                    accent: Theme.brand
                )
            }
            if !release.bugFixes.isEmpty {
                bulletSection(
                    title: "Bug Fixes",
                    icon: "wrench.and.screwdriver.fill",
                    items: release.bugFixes,
                    accent: Theme.warning
                )
            }
            commitHashRow(release.commitHash)
        }
        .padding(.vertical, 12)
    }

    private func bulletSection(title: String, icon: String, items: [String], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent.opacity(0.6))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func commitHashRow(_ hash: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(hash)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("git commit")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                .fill(Theme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 1)
                )
        )
        .contextMenu {
            Button {
                UIPasteboard.general.string = hash
            } label: {
                Label("Copy commit hash", systemImage: "doc.on.doc")
            }
        }
    }

    private func typeBadge(_ type: AppRelease.UpdateType) -> some View {
        let color: Color
        switch type {
        case .major: color = Theme.brand
        case .minor: color = Theme.accent
        case .patch: color = Theme.textSecondary
        }
        return Text(type.label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
