import SwiftUI

/// Native in-app Privacy Policy (Account → About). Not a web view.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            TitlePillCollapseReporter()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy Policy")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Last updated: \(PrivacyPolicyContent.lastUpdated)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(PrivacyPolicyContent.intro)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            ForEach(PrivacyPolicyContent.sections) { section in
                Section(section.heading) {
                    ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Privacy Policy", icon: "hand.raised.fill")
            }
        }
    }
}

enum PrivacyPolicyContent {
    static let lastUpdated = "16 July 2026"

    static let intro = """
    This Privacy Policy explains how SURA INVESTMENTS PTY LTD ("we", "our", or "us") collects, uses, stores, and protects personal information when you use the Rosterra application for iOS, iPadOS, and macOS, and our related website.

    By using Rosterra, you acknowledge that your personal information will be handled in accordance with this Privacy Policy.
    """

    struct Section: Identifiable {
        let id: String
        let heading: String
        let paragraphs: [String]
    }

    static let sections: [Section] = [
        Section(id: "collect", heading: "Information We Collect", paragraphs: [
            "Depending on how you use Rosterra, we may collect the following information:",
        ]),
        Section(id: "account", heading: "Account and Profile Information", paragraphs: [
            "Your employer may provide information including:",
            "• Full name\n• Email address\n• Phone number (where provided)\n• Employment role\n• Workplace or team assignment",
            "This information is used to create and manage your account.",
        ]),
        Section(id: "tax", heading: "Tax and Employment Identity", paragraphs: [
            "Your manager may store employment identity details for payroll and Australian tax (ATO) record-keeping, including:",
            "• Date of birth\n• Address\n• Tax File Number (TFN)\n• Employee identifiers",
            "TFN is manager-only and is not shown to staff in the app. Payslips may store the last four digits of your TFN as a snapshot at generation time.",
        ]),
        Section(id: "roster", heading: "Roster and Employment Data", paragraphs: [
            "We collect information required to provide workforce management features, including:",
            "• Work schedules and shifts\n• Availability\n• Leave requests\n• Shift changes and approvals\n• Timesheet entries\n• Attendance records\n• Payslip information made available by your employer\n• Wage assignment history",
        ]),
        Section(id: "location", heading: "Location Information", paragraphs: [
            "When you start or end a shift, the app may record your device location at that moment to verify attendance at your workplace.",
            "Location is captured only around clock-in and clock-out using When-In-Use permission. It is not tracked continuously in the background.",
        ]),
        Section(id: "photos", heading: "Photos", paragraphs: [
            "If you choose to add a profile picture, or attach a task or reference photo, the image you select (from the camera or your photo library) is uploaded and stored with your employer's workspace.",
            "Camera access is used to take photos for those features; photos taken in-app for tasks are not automatically saved to your device photo library.",
        ]),
        Section(id: "device", heading: "Device Information and Diagnostics", paragraphs: [
            "To maintain the security and reliability of the App, we may collect limited technical information, including:",
            "• Device type\n• Operating system version\n• App version\n• Push notification token\n• Crash and diagnostic information via Firebase Crashlytics",
            "This information is used to diagnose issues and keep notifications working. It is not used for advertising.",
        ]),
        Section(id: "analytics", heading: "Usage Analytics", paragraphs: [
            "The Rosterra iOS, iPadOS, and macOS apps do not use Firebase Analytics or advertising identifiers.",
            "The signed-in web version of Rosterra may use Firebase Analytics to collect limited usage events (such as sign-in activity, timesheet submissions, and feature usage) to improve performance and resolve issues. Analytics data is not used for advertising purposes.",
            "Our public marketing website does not use cookies, advertising technologies, or visitor analytics.",
        ]),
        Section(id: "use", heading: "How We Use Your Information", paragraphs: [
            "We use personal information to:",
            "• Provide roster, scheduling, timesheet, leave, attendance, and payslip functionality.\n• Verify shift attendance using location captured at clock-in and clock-out.\n• Manage your account and workplace permissions.\n• Send notifications about roster updates, approvals, reminders, and other work-related events.\n• Respond to support requests.\n• Diagnose crashes and improve reliability.\n• Protect the security and integrity of our services.\n• Comply with legal and regulatory obligations, including payroll and tax record-keeping.",
            "We do not sell your personal information.",
        ]),
        Section(id: "sharing", heading: "Sharing Your Information", paragraphs: [
            "We only share personal information where necessary to operate the service.",
            "This may include:",
            "• Your employer, who controls your workplace data.\n• Google Firebase and Google Cloud Platform, which provide secure hosting, authentication, storage, crash diagnostics, and notification services (and, for the signed-in web app, limited analytics).\n• Service providers who assist in operating the App under appropriate confidentiality and security obligations.\n• Government authorities where required by law.",
            "We do not share your personal information with third parties for marketing purposes.",
        ]),
        Section(id: "storage", heading: "Data Storage and Security", paragraphs: [
            "Rosterra stores data using Google Firebase hosted on Google Cloud Platform.",
            "We use appropriate technical and organisational measures to protect personal information, including:",
            "• Secure authentication.\n• Encrypted network communications (HTTPS/TLS).\n• Access controls restricting data to authorised users within your employer's workspace.\n• Secure storage of authentication credentials using the Apple Keychain.\n• Optional biometric authentication (such as Face ID) on supported Apple devices.",
            "Although we take reasonable steps to protect your information, no method of electronic transmission or storage is completely secure.",
        ]),
        Section(id: "deletion", heading: "Account Deletion and Data Retention", paragraphs: [
            "Accounts are employer-managed.",
            "Staff may request deletion in-app (Account → Delete account). A manager reviews the request. On approval, the account is locked immediately so you cannot sign in. For 30 days the manager may cancel the deletion and reinstate access. After 30 days, Firebase Auth login and push notification tokens are permanently removed.",
            "Managers (business owners) may initiate staff account deletion from the Staff tools in the app. Manager / business-owner accounts cannot be self-deleted in this version for safety. Organisation or owner-account closure will be handled by a Super Admin console when Rosterra becomes multi-tenant SaaS.",
            "We retain personal information only for as long as necessary to provide the service, meet contractual obligations with your employer, and comply with payroll, taxation, employment, and legal record-keeping requirements.",
            "When an account's sign-in is removed, identity and payroll records your employer needs for Australian tax and employment obligations — including name, date of birth, address, TFN, timesheets, shifts, attendance records, payslips, and related wage history — are retained for as long as required by law and your employer's record-keeping policy. They are not wiped solely because login access is removed.",
            "When information is no longer required, it is securely deleted or de-identified where reasonably practicable.",
        ]),
        Section(id: "rights", heading: "Your Rights", paragraphs: [
            "Depending on applicable privacy laws, you may have the right to:",
            "• Request access to your personal information.\n• Request correction of inaccurate or incomplete information.\n• Request deletion of your personal information where permitted by law.\n• Request information about how your personal information is processed.",
            "As most workplace information is managed on behalf of your employer, some requests may need to be handled through your employer.",
            "To make a privacy request, contact:\nEmail: support@sura-roster.com",
        ]),
        Section(id: "children", heading: "Children's Privacy", paragraphs: [
            "Rosterra is designed for workplace use and is not intended for children under the age of 16.",
            "We do not knowingly collect personal information directly from children.",
        ]),
        Section(id: "cookies", heading: "Cookies and Tracking", paragraphs: [
            "Our public website does not use cookies, advertising technologies, or visitor analytics.",
            "Rosterra does not use App Tracking Transparency, advertising identifiers, or third-party advertising trackers.",
            "The iOS, iPadOS, and macOS apps use Firebase Crashlytics for crash diagnostics only. The signed-in web app may use Firebase Analytics as described above.",
        ]),
        Section(id: "transfers", heading: "International Data Transfers", paragraphs: [
            "Because Rosterra uses Google Cloud and Firebase services, your information may be processed or stored on servers located outside Australia. Where this occurs, we take reasonable steps to ensure your personal information receives appropriate protection consistent with applicable privacy laws.",
        ]),
        Section(id: "changes", heading: "Changes to This Privacy Policy", paragraphs: [
            "We may update this Privacy Policy from time to time.",
            "When significant changes are made, we will update the \"Last updated\" date and may notify users through the App or by other appropriate means.",
            "Your continued use of Rosterra after changes take effect constitutes acceptance of the updated Privacy Policy.",
        ]),
        Section(id: "contact", heading: "Contact Us", paragraphs: [
            "If you have questions about this Privacy Policy or our privacy practices, please contact:\n\nSURA INVESTMENTS PTY LTD\nAdelaide, South Australia\nEmail: support@sura-roster.com\nBusiness Address: 66 Wellington Road, Mount Barker, SA, 5251.\nWebsite: https://sura-roster.com/home",
        ]),
    ]
}
