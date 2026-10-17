import AppKit
import Metal
import QuartzCore

/// Native CAMetalLayer surface; safe to embed in the legacy screensaver hierarchy.
@objc(OceanMetalView)
final class OceanMetalView: NSView {
    private var renderer: OceanMetalRenderer?
    private var renderTimer: Timer?
    private var lastTime = CACurrentMediaTime()
    private var lastSolarUpdate = Date.distantPast
    private var celestial: CelestialFrame?
    private var preferences = OceanPreferences.load()
    private let preview: Bool
    private var active = false
    private var firstFrame = true
    private var failure: String?
    var onEvent: ((String, String?) -> Void)?
    var diagnosticDate: Date?
    var diagnosticCoordinate: GeographicCoordinate?

    init(frame: NSRect, bundle: Bundle, preview: Bool) {
        self.preview = preview
        super.init(frame: frame)
        wantsLayer = true
        do {
            let renderer = try OceanMetalRenderer(bundle: bundle)
            self.renderer = renderer
            if let surface = layer as? CAMetalLayer {
                surface.device = renderer.device
                surface.pixelFormat = .bgra8Unorm
                surface.framebufferOnly = false
                surface.isOpaque = true
                surface.backgroundColor = NSColor.black.cgColor
                surface.maximumDrawableCount = 3
            }
        } catch { showFailure(error.localizedDescription) }
    }

    required init?(coder: NSCoder) { nil }
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func start() {
        guard !active else { return }
        if let failure { onEvent?("error", failure); return }
        active = true
        lastTime = CACurrentMediaTime()
        updateSun()
        onEvent?("ready", nil)
        let timer = Timer(timeInterval: 1 / Double(preferences.framesPerSecond), repeats: true) { [weak self] _ in self?.drawOcean() }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
        drawOcean()
    }
    func stop() {
        active = false
        renderTimer?.invalidate(); renderTimer = nil
    }
    func tearDown() { stop() }
    deinit { renderTimer?.invalidate() }

    func updateSun() {
        preferences = OceanPreferences.load()
        celestial = CelestialFrame.calculate(date: diagnosticDate ?? Date(), coordinate: diagnosticCoordinate ?? preferences.coordinate)
        lastSolarUpdate = Date()
    }

    private func drawOcean() {
        guard active, failure == nil, let renderer, let surface = layer as? CAMetalLayer,
              window != nil, bounds.width > 0, bounds.height > 0 else { return }
        if Date().timeIntervalSince(lastSolarUpdate) >= 10 { updateSun() }
        guard let celestial else { return }
        let scale = window?.backingScaleFactor ?? 1
        let cap = preview ? min(1280, preferences.maxPixelDimension) : preferences.maxPixelDimension
        let pixels = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let shrink = min(1, CGFloat(cap) / max(pixels.width, pixels.height))
        let size = CGSize(width: max(1, (pixels.width * shrink).rounded()), height: max(1, (pixels.height * shrink).rounded()))
        if surface.drawableSize != size { surface.drawableSize = size }
        surface.contentsScale = scale
        guard let drawable = surface.nextDrawable() else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, max(0, now - lastTime)))
        lastTime = now
        do {
            try renderer.render(width: Int(size.width), height: Int(size.height), deltaTime: dt, celestial: celestial, drawable: drawable) { [weak self] error in
                guard let self else { return }
                if let error { self.showFailure(error.localizedDescription) }
                else if self.firstFrame { self.firstFrame = false; self.onEvent?("frame", nil) }
            }
        } catch { showFailure(error.localizedDescription) }
    }

    private func showFailure(_ message: String) {
        guard failure == nil else { return }
        failure = message
        stop()
        onEvent?("error", message)
        NSLog("Ocean Metal error: %@", message)
        let label = NSTextField(wrappingLabelWithString: "Ocean could not start\n\n" + message)
        label.textColor = .white
        label.frame = bounds.insetBy(dx: 24, dy: 24)
        label.autoresizingMask = [.width, .height]
        addSubview(label)
    }

    @objc var oceanDiagnostics: [String: Any] {
        ["renderer": "Metal", "state": failure != nil ? "error" : active ? "running" : "paused",
         "frames": renderer?.completedFrames ?? 0, "width": renderer?.output?.width ?? 0,
         "height": renderer?.output?.height ?? 0, "sunElevation": celestial?.sun.elevationDegrees ?? 0,
         "sunAzimuth": celestial?.sun.azimuthDegrees ?? 0, "heading": celestial?.viewAzimuthDegrees ?? 0,
         "viewTarget": celestial?.isNight == true ? "Moon" : "Sun",
         "moonAzimuth": celestial?.moon.azimuthDegrees ?? 0,
         "moonElevation": celestial?.moon.elevationDegrees ?? 0,
         "moonIlluminatedFraction": celestial?.moon.illuminatedFraction ?? 0,
         "framesPerSecond": preferences.framesPerSecond, "error": failure ?? ""]
    }
    func diagnostics(_ completion: @escaping (Any?, Error?) -> Void) { completion(oceanDiagnostics, nil) }
    func snapshot(to url: URL, completion: @escaping (Error?) -> Void) {
        do {
            guard let renderer else { throw OceanMetalRenderer.RenderError(message: failure ?? "Metal renderer unavailable.") }
            try renderer.snapshot(to: url); completion(nil)
        } catch { completion(error) }
    }
    @objc func saveOceanSnapshot(_ path: String) -> Bool {
        do { try renderer?.snapshot(to: URL(fileURLWithPath: path)); return renderer != nil } catch { return false }
    }
    @objc func captureOceanSnapshot(_ path: String) -> NSNumber { NSNumber(value: saveOceanSnapshot(path)) }
}
