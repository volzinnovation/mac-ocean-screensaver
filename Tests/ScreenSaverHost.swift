import AppKit
import ScreenSaver

/// Loads the actual compiled native plug-in without installing or changing preferences.
final class ScreenSaverSmokeHost: NSObject {
    private var window: NSWindow!
    private var saver: ScreenSaverView!
    private var metalView: NSView?
    private var retiredMetalView: NSView?
    private var pollTimer: Timer?
    private var timeoutTimer: Timer?
    private var phase = 0
    private var initialFrames = 0
    private var stoppedFrames = 0
    private var firstIdentity: ObjectIdentifier?
    private var continuousSince: Date?
    private var lastProgress = Date()
    private var previousFrames = 0
    private let screenshotURL: URL
    private let bundleURL: URL

    init(bundleURL: URL, screenshotURL: URL) {
        self.bundleURL = bundleURL
        self.screenshotURL = screenshotURL
    }

    func start() {
        guard let bundle = Bundle(url: bundleURL) else { fail("Cannot open saver bundle: \(bundleURL.path)") }
        do { try bundle.loadAndReturnError() } catch { fail("Cannot load saver bundle: \(error)") }
        guard let saverClass = bundle.principalClass as? ScreenSaverView.Type else {
            fail("The bundle principal class is not a ScreenSaverView.")
        }
        let frame = NSRect(x: 0, y: 0, width: 960, height: 600)
        guard let instance = saverClass.init(frame: frame, isPreview: true) else {
            fail("The saver principal class could not create its preview view.")
        }
        saver = instance
        saver.autoresizingMask = [.width, .height]
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ocean Native Screensaver Verification"
        window.contentView = saver
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        saver.startAnimation()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            self?.fail("Timed out waiting for the native screensaver to render (phase \(self?.phase ?? -1)).")
        }
    }

    private func findMetalView(_ view: NSView) -> NSView? {
        guard !view.className.contains("WKWebView") else { fail("A WebKit view remains in the screensaver hierarchy.") }
        if view.responds(to: NSSelectorFromString("oceanDiagnostics")) { return view }
        for child in view.subviews {
            if let metal = findMetalView(child) { return metal }
        }
        return nil
    }

    private func diagnostics(_ view: NSView) -> [String: Any] {
        guard let data = view.value(forKey: "oceanDiagnostics") as? [String: Any] else { fail("Native diagnostics unavailable.") }
        guard data["renderer"] as? String == "Metal" else { fail("The screensaver is not using native Metal: \(data)") }
        guard data["state"] as? String != "error" else { fail("Native renderer error: \(data["error"] ?? "unknown")") }
        return data
    }

    private func poll() {
        guard phase < 3 else { return }
        if metalView == nil { metalView = findMetalView(saver) }
        guard let metal = metalView else { return }
        let data = diagnostics(metal)
        guard data["state"] as? String == "running", let frames = data["frames"] as? Int, frames >= 12 else { return }
        guard let target = data["viewTarget"] as? String, target == "Sun" || target == "Moon" else {
            fail("The native scene did not report its celestial viewing target: \(data)")
        }
        let azimuthKey = target == "Moon" ? "moonAzimuth" : "sunAzimuth"
        guard let heading = data["heading"] as? Double, let azimuth = data[azimuthKey] as? Double,
              abs(heading - azimuth) < 0.000001 else { fail("Camera heading does not follow the \(target) azimuth: \(data)") }
        guard let fraction = data["moonIlluminatedFraction"] as? Double, (0...1).contains(fraction) else {
            fail("The lunar illuminated fraction is invalid: \(data)")
        }
        guard let width = data["width"] as? Int, let height = data["height"] as? Int,
              width > 0, height > 0, max(width, height) <= 1280 else { fail("Invalid preview render dimensions: \(data)") }
        switch phase {
        case 0:
            if continuousSince == nil {
                continuousSince = Date()
                lastProgress = Date()
                previousFrames = frames
                log("Native preview started: \(data)")
            }
            if frames > previousFrames { lastProgress = Date(); previousFrames = frames }
            guard Date().timeIntervalSince(lastProgress) < 3 else { fail("Native frame count stopped advancing after startup.") }
            // Keep running well past the old WebKit host's three-second failure.
            guard Date().timeIntervalSince(continuousSince!) >= 36 else { return }
            log("Native rendering sustained for 36 seconds: \(data)")
            firstIdentity = ObjectIdentifier(metal)
            initialFrames = frames
            snapshot(metal)
            window.setContentSize(NSSize(width: 90, height: 60))
            phase = 1
        case 1:
            guard frames >= initialFrames + 4, max(width, height) <= 256 else { return }
            log("Tiny native preview rendered without GPU errors: \(width)×\(height)")
            phase = 3
            verifyStop(metal)
        case 2:
            guard ObjectIdentifier(metal) != firstIdentity else { fail("Restart reused the torn-down Metal view.") }
            log("Native restart rendered: \(data)")
            finish()
        default:
            break
        }
    }

    private func snapshot(_ metal: NSView) {
        let selector = NSSelectorFromString("saveOceanSnapshot:")
        guard metal.responds(to: selector) else { fail("The native snapshot API is missing.") }
        // A BOOL return must be called through its real IMP signature, not perform().
        typealias SaveSnapshot = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let save = unsafeBitCast(metal.method(for: selector), to: SaveSnapshot.self)
        guard save(metal, selector, screenshotURL.path as NSString) else { fail("Could not capture the native rendered texture.") }
        guard FileManager.default.fileExists(atPath: screenshotURL.path),
              let image = NSImage(contentsOf: screenshotURL), image.size.width > 0 else { fail("Native snapshot is empty.") }
        log("Native GPU snapshot saved: \(screenshotURL.path)")
    }

    private func verifyStop(_ metal: NSView) {
        retiredMetalView = metal
        saver.stopAnimation()
        guard saver.subviews.isEmpty else { fail("stopAnimation() left rendering views attached.") }
        metalView = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let retired = self.retiredMetalView else { return }
            let data = self.diagnostics(retired)
            guard data["state"] as? String == "paused", let frames = data["frames"] as? Int else {
                self.fail("Stopped native renderer did not pause: \(data)")
            }
            self.stoppedFrames = frames
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.verifyPausedFrames() }
        }
    }

    private func verifyPausedFrames() {
        guard let retired = retiredMetalView else { fail("Retired renderer disappeared during pause verification.") }
        let data = diagnostics(retired)
        guard data["frames"] as? Int == stoppedFrames else { fail("The stopped native renderer continued submitting frames.") }
        log("Native stop removed its scene and paused GPU submission at frame \(stoppedFrames).")
        retiredMetalView = nil
        window.setContentSize(NSSize(width: 960, height: 600))
        saver.startAnimation()
        phase = 2
    }

    private func log(_ message: String) { print(message); fflush(stdout) }

    private func finish() -> Never {
        pollTimer?.invalidate()
        timeoutTimer?.invalidate()
        saver.stopAnimation()
        window.orderOut(nil)
        log("PASS: compiled native Metal screensaver sustains rendering, follows its Sun or Moon target, resizes, stops and restarts.")
        exit(0)
    }

    private func fail(_ message: String) -> Never {
        print("FAIL: \(message)")
        fflush(stdout)
        exit(1)
    }
}

@main
struct ScreenSaverHostMain {
    static func main() {
        guard CommandLine.arguments.count == 3 else {
            fputs("Usage: ScreenSaverHost /absolute/path/Ocean.saver /absolute/path/preview.png\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let host = ScreenSaverSmokeHost(bundleURL: URL(fileURLWithPath: CommandLine.arguments[1]),
                                       screenshotURL: URL(fileURLWithPath: CommandLine.arguments[2]))
        host.start()
        app.run()
        withExtendedLifetime(host) {}
    }
}
