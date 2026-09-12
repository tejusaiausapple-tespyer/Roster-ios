#if targetEnvironment(macCatalyst)
import SwiftUI

struct MacTableColumn {
    let id: String
    let title: String
    let width: CGFloat?
    let minWidth: CGFloat?
    let maxWidth: CGFloat?
    let alignment: Alignment
    let isSortable: Bool

    init(
        id: String,
        title: String,
        width: CGFloat? = nil,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        alignment: Alignment = .leading,
        isSortable: Bool = false
    ) {
        self.id = id
        self.title = title
        self.width = width
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.alignment = alignment
        self.isSortable = isSortable
    }
}

struct MacTable<Item: Identifiable, RowContent: View>: View {
    private let columns: [MacTableColumn]
    private let items: [Item]
    private let selectedId: Item.ID?
    private let sortColumnId: String?
    private let isAscending: Bool
    private let onSelect: ((Item) -> Void)?
    private let onSort: ((String) -> Void)?
    private let rowContent: (Item) -> RowContent

    init(
        columns: [MacTableColumn],
        items: [Item],
        selectedId: Item.ID? = nil,
        sortColumnId: String? = nil,
        isAscending: Bool = true,
        onSelect: ((Item) -> Void)? = nil,
        onSort: ((String) -> Void)? = nil,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        self.columns = columns
        self.items = items
        self.selectedId = selectedId
        self.sortColumnId = sortColumnId
        self.isAscending = isAscending
        self.onSelect = onSelect
        self.onSort = onSort
        self.rowContent = rowContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                ForEach(columns, id: \.id) { col in
                    Button {
                        if col.isSortable {
                            onSort?(col.id)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(col.title)
                                .font(MacType.captionStrong)
                                .foregroundStyle(sortColumnId == col.id ? MacColor.accent : MacColor.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            if sortColumnId == col.id {
                                Image(systemName: isAscending ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(MacColor.accent)
                            }
                        }
                        .frame(maxWidth: col.maxWidth ?? .infinity, alignment: col.alignment)
                    }
                    .buttonStyle(.plain)
                    .disabled(!col.isSortable)
                    .padding(.horizontal, MacSpace.md)
                    .padding(.vertical, MacSpace.sm)
                    .frame(width: col.width)
                    .frame(minWidth: col.minWidth)
                }
            }
            .background(MacColor.tableHeaderBackground)
            .overlay(
                Rectangle()
                    .fill(MacColor.separator)
                    .frame(height: 1),
                alignment: .bottom
            )

            // Rows
            if items.isEmpty {
                MacEmptyState(
                    title: "No Data",
                    subtitle: "There are no records to display.",
                    icon: "tray"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(MacSpace.xxl)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            MacTableRowContainer(
                                isSelected: selectedId == item.id,
                                onSelect: { onSelect?(item) }
                            ) {
                                rowContent(item)
                            }
                        }
                    }
                }
            }
        }
        .background(MacColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MacRadius.large, style: .continuous)
                .strokeBorder(MacColor.cardBorder, lineWidth: 1)
        )
    }
}

private struct MacTableRowContainer<Content: View>: View {
    let isSelected: Bool
    let onSelect: () -> Void
    let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground)
                .overlay(
                    Rectangle()
                        .fill(MacColor.separator.opacity(0.6))
                        .frame(height: 1),
                    alignment: .bottom
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MacMotion.fast) {
                isHovered = hovering
            }
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return MacColor.tableRowSelected
        } else if isHovered {
            return MacColor.tableRowHover
        } else {
            return Color.clear
        }
    }
}
#endif
