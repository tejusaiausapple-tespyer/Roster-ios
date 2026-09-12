#if targetEnvironment(macCatalyst)
import UIKit
import SwiftUI
import ObjectiveC

enum MacWindow {
    /// Target fraction of the usable Mac desktop (between menu bar and Dock).
    private static let screenFillRatio: CGFloat = 0.85

    static let minimumSize = CGSize(width: 900, height: 600)
    /// Catalyst treats a missing maximum as equal to the minimum, which
    /// freezes the window so it cannot be resized at all.
    static let maximumSize = CGSize(width: 8000, height: 8000)

    @MainActor private static var didScheduleDefaultGeometry = false

    /// Size used by `WindowGroup.defaultSize` — 85% of the detected Mac screen.
    static var defaultSize: CGSize {
        preferredSize(for: detectDisplay().size)
    }

    /// Dynamically update the macOS titlebar text.
    @MainActor
    static func setTitle(_ title: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        windowScene.title = title
    }

    /// Toggle the native macOS zoom state (the standard title-bar double-click
    /// behavior) without replacing the Catalyst titlebar or window controls.
    @MainActor
    static func toggleZoom() {
        guard
            let applicationClass = NSClassFromString("NSApplication") as? NSObject.Type,
            let application = applicationClass
                .perform(NSSelectorFromString("sharedApplication"))?
                .takeUnretainedValue() as? NSObject
        else { return }

        let keyWindowSelector = NSSelectorFromString("keyWindow")
        let mainWindowSelector = NSSelectorFromString("mainWindow")
        let window: NSObject? = {
            if application.responds(to: keyWindowSelector),
               let value = application.perform(keyWindowSelector)?.takeUnretainedValue() as? NSObject {
                return value
            }
            if application.responds(to: mainWindowSelector) {
                return application.perform(mainWindowSelector)?.takeUnretainedValue() as? NSObject
            }
            return nil
        }()

        let zoomSelector = NSSelectorFromString("performZoom:")
        guard let window, window.responds(to: zoomSelector) else { return }
        window.perform(zoomSelector, with: nil)
    }

    @MainActor
    static func configureAllScenes() {
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                configureWindowScene(windowScene)
            }
        }
    }

    /// Unified, low-noise titlebar, then auto-size to ~85% of the Mac display.
    @MainActor
    static func configureWindowScene(_ windowScene: UIWindowScene) {
        windowScene.sizeRestrictions?.minimumSize = minimumSize
        windowScene.sizeRestrictions?.maximumSize = maximumSize

        guard let titlebar = windowScene.titlebar else { return }
        // SwiftUI supplies the centered navigation title. Hiding the separate
        // window title avoids rendering the destination twice.
        titlebar.titleVisibility = .hidden
        titlebar.toolbarStyle = .unified
        titlebar.separatorStyle = .none
        titlebar.autoHidesToolbarInFullScreen = false
    }

    // MARK: - Screen detection + resize

    /// Called from a UIKit view controller after it is attached to the actual
    /// Catalyst window. SwiftUI `onAppear` can occur before this point.
    @MainActor
    static func sceneDidBecomeVisible(_ windowScene: UIWindowScene) {
        configureWindowScene(windowScene)
        guard !didScheduleDefaultGeometry else { return }
        didScheduleDefaultGeometry = true
        schedulePreferredGeometry(for: windowScene)
    }

    /// Apply after activation and again while macOS finishes restoring its
    /// persisted window frame. This runs only once per app launch, so later
    /// user-driven resizing is never overridden.
    @MainActor
    private static func schedulePreferredGeometry(for windowScene: UIWindowScene) {
        Task { @MainActor in
            // SwiftUI can appear before the Catalyst scene becomes active.
            // Wait briefly instead of consuming the one launch-time resize.
            for _ in 0..<20 where windowScene.activationState != .foregroundActive {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            guard windowScene.activationState == .foregroundActive else {
                didScheduleDefaultGeometry = false
                return
            }

            applyPreferredGeometry(to: windowScene)

            for delay in [150_000_000, 350_000_000, 700_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delay)
                guard windowScene.activationState == .foregroundActive else { continue }
                applyPreferredGeometry(to: windowScene)
            }
        }
    }

    @MainActor
    private static func applyPreferredGeometry(to windowScene: UIWindowScene) {
        let display = detectDisplay(preferring: windowScene)
        let size = preferredSize(for: display.size)
        let origin = CGPoint(
            x: floor(display.frame.minX + (display.frame.width - size.width) / 2),
            y: floor(display.frame.minY + (display.frame.height - size.height) / 2)
        )
        let frame = CGRect(origin: origin, size: size)
        windowScene.requestGeometryUpdate(
            UIWindowScene.GeometryPreferences.Mac(systemFrame: frame)
        )
    }

    private static func preferredSize(for screenSize: CGSize) -> CGSize {
        CGSize(
            width: max(floor(screenSize.width * screenFillRatio), minimumSize.width),
            height: max(floor(screenSize.height * screenFillRatio), minimumSize.height)
        )
    }

    /// Prefer AppKit `NSScreen.visibleFrame` (excludes menu bar + Dock, Mac
    /// global coords). Fall back to the UIWindowScene / UIScreen bounds.
    private static func detectDisplay(preferring windowScene: UIWindowScene? = nil) -> (size: CGSize, frame: CGRect) {
        if let mac = macVisibleFrame() {
            return (mac.size, mac)
        }

        if let scene = windowScene {
            let bounds = scene.screen.bounds
            return (bounds.size, bounds)
        }

        let bounds = UIScreen.main.bounds
        return (bounds.size, bounds)
    }

    /// Reads `NSScreen.mainScreen.visibleFrame` through the Objective-C runtime.
    /// AppKit symbols aren't available to Swift on Catalyst, but NSScreen exists
    /// at runtime on Mac and gives the real usable desktop rectangle.
    private static func macVisibleFrame() -> CGRect? {
        guard
            let screenClass = NSClassFromString("NSScreen") as? NSObject.Type
        else { return nil }

        let mainScreenSelector = NSSelectorFromString("mainScreen")
        guard screenClass.responds(to: mainScreenSelector),
              let mainScreen = screenClass.perform(mainScreenSelector)?.takeUnretainedValue() as? NSObject
        else { return nil }

        // Prefer visibleFrame (menu bar + Dock excluded). Fall back to frame.
        if mainScreen.responds(to: NSSelectorFromString("visibleFrame")),
           let visible = mainScreen.value(forKey: "visibleFrame") as? CGRect,
           visible.width > 0, visible.height > 0 {
            return visible
        }

        if mainScreen.responds(to: NSSelectorFromString("frame")),
           let frame = mainScreen.value(forKey: "frame") as? CGRect,
           frame.width > 0, frame.height > 0 {
            return frame
        }

        return nil
    }
}

/// Bridges the reliable UIKit window lifecycle into the SwiftUI app root.
struct MacWindowConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard let windowScene = view.window?.windowScene else { return }
            MacWindow.sceneDidBecomeVisible(windowScene)
        }
    }
}
#endif
