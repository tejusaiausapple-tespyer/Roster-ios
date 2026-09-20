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

/// Forces a SwiftUI `.sheet` on Mac Catalyst to ~`widthFraction` × `heightFraction`
/// of the key app window. Frame hints alone are often ignored by Catalyst sheets.
struct MacFractionalSheetSizer: UIViewControllerRepresentable {
    var widthFraction: CGFloat
    var heightFraction: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller(widthFraction: widthFraction, heightFraction: heightFraction)
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.widthFraction = widthFraction
        uiViewController.heightFraction = heightFraction
        uiViewController.applyPreferredSizeIfNeeded()
    }

    static func activeWindowSize() -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first {
            return window.bounds.size
        }
        if let scene {
            return scene.coordinateSpace.bounds.size
        }
        return CGSize(width: 1440, height: 900)
    }

    final class Controller: UIViewController {
        var widthFraction: CGFloat
        var heightFraction: CGFloat

        init(widthFraction: CGFloat, heightFraction: CGFloat) {
            self.widthFraction = widthFraction
            self.heightFraction = heightFraction
            super.init(nibName: nil, bundle: nil)
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyPreferredSizeIfNeeded()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyPreferredSizeIfNeeded()
        }

        func applyPreferredSizeIfNeeded() {
            guard let host = sheetHostController() else { return }
            let windowSize = view.window?.bounds.size
                ?? Self.parentWindowSize(from: host)
                ?? MacFractionalSheetSizer.activeWindowSize()
            let target = CGSize(
                width: max(960, windowSize.width * widthFraction),
                height: max(680, windowSize.height * heightFraction)
            )
            if abs(host.preferredContentSize.width - target.width) > 1
                || abs(host.preferredContentSize.height - target.height) > 1 {
                host.preferredContentSize = target
            }
        }

        private func sheetHostController() -> UIViewController? {
            var current: UIViewController? = self
            while let controller = current {
                if controller.presentingViewController != nil {
                    return controller
                }
                if let parent = controller.parent {
                    current = parent
                    continue
                }
                return controller
            }
            return nil
        }

        private static func parentWindowSize(from host: UIViewController) -> CGSize? {
            if let size = host.view.window?.bounds.size, size.width > 0, size.height > 0 {
                return size
            }
            if let size = host.presentingViewController?.view.window?.bounds.size,
               size.width > 0, size.height > 0 {
                return size
            }
            return nil
        }
    }
}

/// Native Mac print panel for PDF files under Mac Catalyst.
///
/// `UIPrintInteractionController` is unreliable on Catalyst and often shows
/// AppKit's "This application does not support printing" alert. This helper
/// talks to AppKit (`NSPrintOperation`) through the Objective-C runtime instead.
@MainActor
enum MacPDFPrinter {
    /// Presents the Mac print dialog for the PDF at `url`.
    @discardableResult
    static func print(at url: URL, jobName: String) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        if printWithAppKit(data: data, jobName: jobName) {
            return true
        }
        // Fallback: open in Preview so the user can still File → Print.
        UIApplication.shared.open(url)
        return true
    }

    private static func printWithAppKit(data: Data, jobName: String) -> Bool {
        guard let imageView = makePDFImageView(data: data) else { return false }

        guard
            let printInfoClass = NSClassFromString("NSPrintInfo") as? NSObject.Type,
            let shared = printInfoClass.perform(NSSelectorFromString("sharedPrintInfo"))?
                .takeUnretainedValue() as? NSObject,
            let printInfo = shared.perform(NSSelectorFromString("copy"))?
                .takeUnretainedValue() as? NSObject
        else { return false }

        printInfo.setValue(jobName, forKey: "jobName")
        printInfo.setValue(0, forKey: "orientation") // NSPortraitOrientation
        printInfo.setValue(2, forKey: "horizontalPagination") // NSFitPagination
        printInfo.setValue(2, forKey: "verticalPagination")

        guard let opClass = NSClassFromString("NSPrintOperation") as? NSObject.Type else {
            return false
        }

        let makeSel = NSSelectorFromString("printOperationWithView:printInfo:")
        guard
            opClass.responds(to: makeSel),
            let operation = opClass.perform(makeSel, with: imageView, with: printInfo)?
                .takeUnretainedValue() as? NSObject
        else { return false }

        operation.setValue(true, forKey: "showsPrintPanel")
        operation.setValue(true, forKey: "showsProgressPanel")
        if operation.responds(to: NSSelectorFromString("setJobTitle:")) {
            operation.setValue(jobName, forKey: "jobTitle")
        }

        let runSel = NSSelectorFromString("runOperation")
        guard operation.responds(to: runSel) else { return false }
        _ = operation.perform(runSel)
        return true
    }

    /// Stacks every PDF page into one tall image so multi-page pay runs print fully.
    private static func makePDFImageView(data: Data) -> NSObject? {
        guard
            let provider = CGDataProvider(data: data as CFData),
            let pdf = CGPDFDocument(provider),
            pdf.numberOfPages > 0,
            let firstPage = pdf.page(at: 1)
        else {
            return makeImageView(fromImageData: data, forceSize: nil)
        }

        let pageSize = firstPage.getBoxRect(.mediaBox).size
        let pageCount = pdf.numberOfPages
        let canvasSize = CGSize(
            width: max(pageSize.width, 1),
            height: max(pageSize.height, 1) * CGFloat(pageCount)
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let combined = UIGraphicsImageRenderer(size: canvasSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))

            for index in 1...pageCount {
                guard let page = pdf.page(at: index) else { continue }
                let box = page.getBoxRect(.mediaBox)
                let y = pageSize.height * CGFloat(index - 1)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: y + pageSize.height)
                ctx.cgContext.scaleBy(x: 1, y: -1)
                let s = min(pageSize.width / max(box.width, 1), pageSize.height / max(box.height, 1))
                ctx.cgContext.translateBy(
                    x: (pageSize.width - box.width * s) / 2,
                    y: (pageSize.height - box.height * s) / 2
                )
                ctx.cgContext.scaleBy(x: s, y: s)
                ctx.cgContext.drawPDFPage(page)
                ctx.cgContext.restoreGState()
            }
        }

        guard let png = combined.pngData() else {
            return makeImageView(fromImageData: data, forceSize: nil)
        }
        return makeImageView(fromImageData: png, forceSize: canvasSize)
    }

    private static func makeImageView(fromImageData data: Data, forceSize: CGSize?) -> NSObject? {
        guard
            let imageClass = NSClassFromString("NSImage") as? NSObject.Type,
            let imageAlloc = imageClass.perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue() as? NSObject,
            let image = imageAlloc.perform(NSSelectorFromString("initWithData:"), with: data)?
                .takeUnretainedValue() as? NSObject
        else { return nil }

        let size: CGSize = {
            if let forceSize, forceSize.width > 0, forceSize.height > 0 { return forceSize }
            return (image.value(forKey: "size") as? CGSize) ?? CGSize(width: 595, height: 842)
        }()

        guard
            let viewClass = NSClassFromString("NSImageView") as? NSObject.Type,
            let viewAlloc = viewClass.perform(NSSelectorFromString("alloc"))?
                .takeUnretainedValue() as? NSObject
        else { return nil }

        let frame = CGRect(origin: .zero, size: size)
        let view: NSObject
        if let inited = invokeInitWithFrame(viewAlloc, frame: frame) {
            view = inited
        } else if let inited = viewAlloc.perform(NSSelectorFromString("init"))?
            .takeUnretainedValue() as? NSObject {
            _ = invokeSetFrame(inited, frame)
            view = inited
        } else {
            return nil
        }

        view.setValue(image, forKey: "image")
        view.setValue(2, forKey: "imageScaling")
        return view
    }

    private static func invokeInitWithFrame(_ object: NSObject, frame: CGRect) -> NSObject? {
        let selector = NSSelectorFromString("initWithFrame:")
        let cls: AnyClass? = object_getClass(object)
        guard let method = (cls.flatMap { class_getInstanceMethod($0, selector) })
                ?? class_getInstanceMethod(type(of: object), selector)
        else { return nil }
        let imp = method_getImplementation(method)
        typealias Fn = @convention(c) (AnyObject, Selector, CGRect) -> Unmanaged<AnyObject>?
        return unsafeBitCast(imp, to: Fn.self)(object, selector, frame)?
            .takeUnretainedValue() as? NSObject
    }

    private static func invokeSetFrame(_ object: NSObject, _ frame: CGRect) -> Bool {
        let selector = NSSelectorFromString("setFrame:")
        let cls: AnyClass? = object_getClass(object)
        guard let method = (cls.flatMap { class_getInstanceMethod($0, selector) })
                ?? class_getInstanceMethod(type(of: object), selector)
        else { return false }
        let imp = method_getImplementation(method)
        typealias Fn = @convention(c) (AnyObject, Selector, CGRect) -> Void
        unsafeBitCast(imp, to: Fn.self)(object, selector, frame)
        return true
    }
}
#endif
