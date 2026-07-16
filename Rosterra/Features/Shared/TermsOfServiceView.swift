import SwiftUI

/// Native in-app Terms of Service (Account → About). Not a web view.
struct TermsOfServiceView: View {
    var body: some View {
        List {
            TitlePillCollapseReporter()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Terms of Service")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Effective Date: \(TermsOfServiceContent.effectiveDate)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text(TermsOfServiceContent.intro)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            ForEach(TermsOfServiceContent.sections) { section in
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
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ScreenTitlePill(title: "Terms of Service", icon: "doc.text.fill")
            }
        }
    }
}

enum TermsOfServiceContent {
    static let effectiveDate = "16 July 2026"

    static let intro = """
    These Terms of Service ("Terms") govern your access to and use of Rosterra ("the App"), which is owned and operated by SURA INVESTMENTS PTY LTD ("Company", "we", "our", or "us").

    By creating an account, accessing, or using Rosterra, you agree to be bound by these Terms. If you do not agree to these Terms, you must not use the App.
    """

    struct Section: Identifiable {
        let id: String
        let heading: String
        let paragraphs: [String]
    }

    static let sections: [Section] = [
        Section(id: "1", heading: "1. About Rosterra", paragraphs: [
            "Rosterra is a workforce scheduling and roster management platform designed to help businesses create, manage, and share employee rosters, communicate with team members, manage shift changes, and perform related workforce management functions.",
            "We may update, improve, modify, or discontinue features of the App at any time.",
        ]),
        Section(id: "2", heading: "2. Eligibility", paragraphs: [
            "You must be at least 18 years of age, or the age of legal majority in your jurisdiction, to create an account.",
            "If you register or use the App on behalf of a business or other organization, you represent and warrant that you have the authority to bind that organization to these Terms.",
        ]),
        Section(id: "3", heading: "3. User Accounts", paragraphs: [
            "You agree to:",
            "• Provide accurate, complete, and current registration information.\n• Maintain the security and confidentiality of your login credentials.\n• Notify us promptly of any unauthorized access to your account.\n• Accept responsibility for all activities conducted through your account.",
            "You are responsible for ensuring your account information remains accurate.",
        ]),
        Section(id: "4", heading: "4. Acceptable Use", paragraphs: [
            "You agree not to:",
            "• Use the App for any unlawful or fraudulent purpose.\n• Access another user's account without authorization.\n• Upload malware, viruses, or malicious code.\n• Interfere with the operation, security, or integrity of the App.\n• Attempt to reverse engineer, decompile, or copy any part of the App except where permitted by law.\n• Misuse the App in any way that could harm other users or the Company.",
            "We reserve the right to suspend or terminate accounts that violate these Terms.",
        ]),
        Section(id: "5", heading: "5. Employer and Employee Responsibilities", paragraphs: [
            "Businesses using Rosterra are responsible for:",
            "• Maintaining accurate employee information.\n• Creating and publishing accurate work schedules.\n• Complying with all applicable employment, workplace, and payroll laws.\n• Managing user permissions appropriately.",
            "Employees and team members are responsible for reviewing their assigned schedules and keeping their contact details current.",
        ]),
        Section(id: "6", heading: "6. User Content", paragraphs: [
            "You retain ownership of any schedules, messages, documents, files, or other content you submit to the App.",
            "By uploading content, you grant SURA INVESTMENTS PTY LTD a non-exclusive, worldwide, royalty-free licence to host, process, store, display, and transmit that content solely for the purpose of operating, maintaining, securing, and improving the App.",
            "You represent that you have all necessary rights to upload and share your content.",
        ]),
        Section(id: "7", heading: "7. Privacy", paragraphs: [
            "Our collection, use, and disclosure of personal information are governed by our Privacy Policy.",
            "By using Rosterra, you acknowledge that your personal information will be handled in accordance with our Privacy Policy.",
        ]),
        Section(id: "8", heading: "8. Subscription and Payments", paragraphs: [
            "Where paid subscriptions are offered:",
            "• Subscription fees are charged in advance.\n• Subscription fees are non-refundable except where required by applicable law.\n• Prices may change with reasonable notice.\n• Failure to pay applicable fees may result in suspension or termination of access.\n• Applicable taxes may be charged where required.",
        ]),
        Section(id: "9", heading: "9. Intellectual Property", paragraphs: [
            "Rosterra, including its software, source code, design, branding, logos, graphics, text, documentation, and other content, is owned by SURA INVESTMENTS PTY LTD or its licensors and is protected by applicable intellectual property laws.",
            "No ownership rights are transferred to users through use of the App.",
        ]),
        Section(id: "10", heading: "10. Availability of Service", paragraphs: [
            "While we aim to provide reliable service, we do not guarantee uninterrupted or error-free operation.",
            "Maintenance, upgrades, technical issues, or events beyond our reasonable control may temporarily affect availability.",
        ]),
        Section(id: "11", heading: "11. Third-Party Services", paragraphs: [
            "Rosterra may integrate with third-party services such as payroll providers, calendar services, messaging platforms, authentication providers, or cloud storage providers.",
            "We are not responsible for the availability, functionality, or policies of third-party services.",
        ]),
        Section(id: "12", heading: "12. Disclaimer", paragraphs: [
            "To the maximum extent permitted by law, Rosterra is provided on an \"as is\" and \"as available\" basis.",
            "SURA INVESTMENTS PTY LTD makes no warranties or guarantees that:",
            "• The App will always be available.\n• The App will operate without interruption or errors.\n• Information stored in the App will never be lost.\n• The App will meet every user's specific requirements.",
            "Nothing in these Terms excludes consumer guarantees that cannot legally be excluded under the Australian Consumer Law.",
        ]),
        Section(id: "13", heading: "13. Limitation of Liability", paragraphs: [
            "To the fullest extent permitted by law, SURA INVESTMENTS PTY LTD will not be liable for any indirect, incidental, special, consequential, or punitive damages arising out of or relating to the use of Rosterra.",
            "Where liability cannot be excluded, our liability is limited to the maximum extent permitted by applicable law.",
            "If permitted by law, our total liability for any claim will not exceed the greater of:",
            "• The amount paid by you for the App during the twelve (12) months immediately preceding the claim; or\n• AUD $100.",
        ]),
        Section(id: "14", heading: "14. Indemnity", paragraphs: [
            "You agree to indemnify and hold harmless SURA INVESTMENTS PTY LTD, its directors, officers, employees, contractors, and affiliates from any claims, liabilities, damages, costs, or expenses arising from:",
            "• Your use of the App.\n• Your breach of these Terms.\n• Your violation of applicable laws or the rights of another person.",
        ]),
        Section(id: "15", heading: "15. Suspension and Termination", paragraphs: [
            "We may suspend or terminate your account immediately if:",
            "• You breach these Terms.\n• You engage in unlawful activity.\n• Your use poses a security risk.\n• You misuse or abuse the App.",
            "Accounts are employer-managed. Staff may request account deletion in-app; a manager reviews and may approve, after which access is locked and sign-in is removed after a grace period as described in our Privacy Policy. Managers may delete staff accounts in the App. Manager / business-owner accounts are not self-deletable in this version; organisation closure will be handled by Super Admin when Rosterra becomes multi-tenant SaaS.",
            "You may stop using Rosterra at any time.",
        ]),
        Section(id: "16", heading: "16. Data Retention", paragraphs: [
            "We may retain account information and associated records for legal, regulatory, security, operational, and backup purposes in accordance with our Privacy Policy and applicable law.",
            "Where required for Australian tax, payroll, and employment record-keeping, identity and payroll-related records (including name, date of birth, address, Tax File Number, timesheets, and payslips) may be retained after sign-in access is removed.",
        ]),
        Section(id: "17", heading: "17. Changes to These Terms", paragraphs: [
            "We may amend these Terms from time to time.",
            "Where changes are material, we will provide reasonable notice through the App or by email. Continued use of Rosterra after the updated Terms take effect constitutes acceptance of the revised Terms.",
        ]),
        Section(id: "18", heading: "18. Governing Law", paragraphs: [
            "These Terms are governed by the laws of the State of South Australia and the laws of the Commonwealth of Australia.",
            "Any dispute arising from these Terms shall be subject to the exclusive jurisdiction of the courts of South Australia, unless applicable law provides otherwise.",
        ]),
        Section(id: "19", heading: "19. Contact Us", paragraphs: [
            "SURA INVESTMENTS PTY LTD\nEmail: support@sura-roster.com\nBusiness Address: 66 Wellington Road, Mount Barker, SA, 5251.\nWebsite: https://sura-roster.com/home",
        ]),
        Section(id: "20", heading: "20. Entire Agreement", paragraphs: [
            "These Terms constitute the entire agreement between you and SURA INVESTMENTS PTY LTD regarding your use of Rosterra and supersede all prior agreements relating to the App.",
        ]),
        Section(id: "21", heading: "21. Severability", paragraphs: [
            "If any provision of these Terms is held to be invalid, illegal, or unenforceable, the remaining provisions will continue in full force and effect.",
        ]),
        Section(id: "22", heading: "22. Waiver", paragraphs: [
            "Our failure to enforce any right or provision under these Terms does not constitute a waiver of that right or provision.",
        ]),
    ]
}
