import SwiftUI
import SafariServices

/// Presents a URL inside the app via `SFSafariViewController` (reader chrome,
/// share, Done) instead of bouncing out to Safari.
struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.brand)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
