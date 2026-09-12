#if targetEnvironment(macCatalyst)
import SwiftUI

// MARK: - Mac Color System

enum MacColor {
    // Brand & Accents
    static let accent = Color.dynamic(light: 0x4F46E5, dark: 0x818CF8) // Indigo 600 / 400
    static let brandStrong = Color(hex: 0x4F46E5)
    static let success = Color.dynamic(light: 0x059669, dark: 0x34D399) // Emerald 600 / 400
    static let warning = Color.dynamic(light: 0xD97706, dark: 0xFBBF24) // Amber 600 / 400
    static let error = Color.dynamic(light: 0xDC2626, dark: 0xF87171)   // Red 600 / 400
    static let info = Color.dynamic(light: 0x2563EB, dark: 0x60A5FA)    // Blue 600 / 400

    // Canvas & Surfaces
    static let windowBackground = Color.dynamic(light: 0xF4F5F8, dark: 0x0F1014)
    static let cardBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x1C1D22)
    static let cardBackgroundSecondary = Color.dynamic(light: 0xF8FAFC, dark: 0x24252B)
    static let cardBorder = Color.dynamic(light: 0xE6E9EF, dark: 0x2E3038)
    static let tableHeaderBackground = Color.dynamic(light: 0xF7F8FB, dark: 0x18191E)
    static let tableRowHover = Color.dynamic(light: 0xF4F6FB, dark: 0x262830)
    static let tableRowSelected = Color.dynamic(light: 0xEEF2FF, dark: 0x282B3E)
    static let separator = Color.dynamic(light: 0xE8EBF0, dark: 0x2A2C34)

    // Sidebar — keep these for leftover call sites; the source list itself
    // uses the system sidebar material / Liquid Glass.
    static let sidebarBackground = Color.clear
    static let sidebarSelection = Color.dynamic(light: 0xEEF2FF, dark: 0x2A2D48)
    static let sidebarSelectionForeground = Color.dynamic(light: 0x4338CA, dark: 0xA5B4FC)
    static let sidebarHover = Color.dynamic(light: 0xEEF0F5, dark: 0x22242C)
    static let sidebarIconWell = Color.dynamic(light: 0xECEFF4, dark: 0x2A2C35)

    // High Contrast Typography (Deep Ink / Crisp Snow)
    static let textPrimary = Color.dynamic(light: 0x0F172A, dark: 0xF8FAFC)   // Slate 900 / 50
    static let textSecondary = Color.dynamic(light: 0x334155, dark: 0xCBD5E1) // Slate 700 / 300 (WCAG AAA)
    static let textTertiary = Color.dynamic(light: 0x64748B, dark: 0x94A3B8)  // Slate 500 / 400
    static let textInverse = Color.white
}

// MARK: - Mac Spacing Tokens

enum MacSpace {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let xxxl: CGFloat = 36
}

// MARK: - Mac Corner Radii

enum MacRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
    static let extraLarge: CGFloat = 18
    static let pill: CGFloat = 999
}

// MARK: - Mac Typography Ramp
// Designed for Mac Catalyst running at full 100% scale (UIDesignRequiresCompatibility = false)

enum MacType {
    static let display = Font.system(size: 38, weight: .bold, design: .default)
    static let windowTitle = Font.system(size: 27, weight: .bold, design: .default)
    static let pageTitle = Font.system(size: 27, weight: .bold, design: .default)
    static let kpiValue = Font.system(size: 33, weight: .bold, design: .default)
    static let sectionHeader = Font.system(size: 19, weight: .semibold, design: .default)
    static let body = Font.system(size: 17, weight: .regular, design: .default)
    static let bodyStrong = Font.system(size: 17, weight: .semibold, design: .default)
    static let subheadline = Font.system(size: 16, weight: .regular, design: .default)
    static let caption = Font.system(size: 14, weight: .regular, design: .default)
    static let captionStrong = Font.system(size: 14, weight: .semibold, design: .default)
    static let badge = Font.system(size: 13, weight: .bold, design: .default)
    static let mono = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let monoStrong = Font.system(size: 16, weight: .semibold, design: .monospaced)
    static let monoLarge = Font.system(size: 21, weight: .bold, design: .monospaced)
}

// MARK: - Mac Motion

enum MacMotion {
    static let fast = Animation.easeOut(duration: 0.12)
    static let normal = Animation.easeInOut(duration: 0.2)
    static let smooth = Animation.spring(response: 0.32, dampingFraction: 0.82)
}

// MARK: - Mac Semantic Status Style

struct MacStatusStyle {
    let label: String
    let foreground: Color
    let background: Color
    let border: Color

    static func forShift(_ status: StaffShiftDisplayStatus) -> MacStatusStyle {
        switch status {
        case .scheduled:
            return MacStatusStyle(
                label: "Scheduled",
                foreground: Color.dynamic(light: 0x1D4ED8, dark: 0x93C5FD),
                background: Color.dynamic(light: 0xEFF6FF, dark: 0x1E293B),
                border: Color.dynamic(light: 0xBFDBFE, dark: 0x3B82F6).opacity(0.4)
            )
        case .awaitingSubmission:
            return MacStatusStyle(
                label: "Awaiting Submit",
                foreground: Color.dynamic(light: 0xB45309, dark: 0xFCD34D),
                background: Color.dynamic(light: 0xFFFBEB, dark: 0x2A2312),
                border: Color.dynamic(light: 0xFDE68A, dark: 0xF59E0B).opacity(0.4)
            )
        case .draft:
            return MacStatusStyle(
                label: "Draft",
                foreground: Color.dynamic(light: 0x475569, dark: 0x94A3B8),
                background: Color.dynamic(light: 0xF1F5F9, dark: 0x1E293B),
                border: Color.dynamic(light: 0xCBD5E1, dark: 0x475569).opacity(0.4)
            )
        case .pending:
            return MacStatusStyle(
                label: "Pending",
                foreground: Color.dynamic(light: 0xB45309, dark: 0xFCD34D),
                background: Color.dynamic(light: 0xFFFBEB, dark: 0x2A2312),
                border: Color.dynamic(light: 0xFDE68A, dark: 0xF59E0B).opacity(0.4)
            )
        case .approved:
            return MacStatusStyle(
                label: "Approved",
                foreground: Color.dynamic(light: 0x047857, dark: 0x6EE7B7),
                background: Color.dynamic(light: 0xECFDF5, dark: 0x0F291E),
                border: Color.dynamic(light: 0xA7F3D0, dark: 0x10B981).opacity(0.4)
            )
        case .rejected:
            return MacStatusStyle(
                label: "Rejected",
                foreground: Color.dynamic(light: 0xB91C1C, dark: 0xFCA5A5),
                background: Color.dynamic(light: 0xFEF2F2, dark: 0x2D1515),
                border: Color.dynamic(light: 0xFECACA, dark: 0xEF4444).opacity(0.4)
            )
        case .absentReported:
            return MacStatusStyle(
                label: "Absent Reported",
                foreground: Color.dynamic(light: 0xC2410C, dark: 0xFDBA74),
                background: Color.dynamic(light: 0xFFF7ED, dark: 0x2D1D13),
                border: Color.dynamic(light: 0xFED7AA, dark: 0xF97316).opacity(0.4)
            )
        case .absent:
            return MacStatusStyle(
                label: "Absent",
                foreground: Color.dynamic(light: 0xB91C1C, dark: 0xFCA5A5),
                background: Color.dynamic(light: 0xFEF2F2, dark: 0x2D1515),
                border: Color.dynamic(light: 0xFECACA, dark: 0xEF4444).opacity(0.4)
            )
        }
    }

    static func forTimesheet(_ status: TimesheetStatus) -> MacStatusStyle {
        switch status {
        case .draft:
            return MacStatusStyle(
                label: "Draft",
                foreground: Color.dynamic(light: 0x475569, dark: 0x94A3B8),
                background: Color.dynamic(light: 0xF1F5F9, dark: 0x1E293B),
                border: Color.dynamic(light: 0xCBD5E1, dark: 0x475569).opacity(0.4)
            )
        case .pending:
            return MacStatusStyle(
                label: "Pending Review",
                foreground: Color.dynamic(light: 0xB45309, dark: 0xFCD34D),
                background: Color.dynamic(light: 0xFFFBEB, dark: 0x2A2312),
                border: Color.dynamic(light: 0xFDE68A, dark: 0xF59E0B).opacity(0.4)
            )
        case .approved:
            return MacStatusStyle(
                label: "Approved",
                foreground: Color.dynamic(light: 0x047857, dark: 0x6EE7B7),
                background: Color.dynamic(light: 0xECFDF5, dark: 0x0F291E),
                border: Color.dynamic(light: 0xA7F3D0, dark: 0x10B981).opacity(0.4)
            )
        case .rejected:
            return MacStatusStyle(
                label: "Rejected",
                foreground: Color.dynamic(light: 0xB91C1C, dark: 0xFCA5A5),
                background: Color.dynamic(light: 0xFEF2F2, dark: 0x2D1515),
                border: Color.dynamic(light: 0xFECACA, dark: 0xEF4444).opacity(0.4)
            )
        case .absentReported:
            return MacStatusStyle(
                label: "Absence Reported",
                foreground: Color.dynamic(light: 0xC2410C, dark: 0xFDBA74),
                background: Color.dynamic(light: 0xFFF7ED, dark: 0x2D1D13),
                border: Color.dynamic(light: 0xFED7AA, dark: 0xF97316).opacity(0.4)
            )
        case .absent:
            return MacStatusStyle(
                label: "Absent",
                foreground: Color.dynamic(light: 0xB91C1C, dark: 0xFCA5A5),
                background: Color.dynamic(light: 0xFEF2F2, dark: 0x2D1515),
                border: Color.dynamic(light: 0xFECACA, dark: 0xEF4444).opacity(0.4)
            )
        }
    }
}
#endif
