import AppKit
import ScreenSaver

@objc(OceanScreenSaverView)
final class OceanScreenSaverView: ScreenSaverView {
    private static var lastLocationRefresh = Date.distantPast
    private var scene: OceanMetalView?
    private var options: NSWindow?
    private var optionsPreferences: OceanPreferences?
    private let latitudeField = NSTextField()
    private let longitudeField = NSTextField()
    private let qualityPopup = NSPopUpButton()
    private let optionsSourceLabel = NSTextField(wrappingLabelWithString: "")
    private let optionsStatusLabel = NSTextField(wrappingLabelWithString: "")

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit { scene?.tearDown() }

    override func startAnimation() {
        super.startAnimation()
        refreshAuthorizedLocation()
        if scene == nil {
            let view = OceanMetalView(frame: bounds, bundle: Bundle(for: Self.self), preview: isPreview)
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            scene = view
        }
        scene?.start()
    }

    override func stopAnimation() {
        scene?.tearDown()
        scene?.removeFromSuperview()
        scene = nil
        super.stopAnimation()
    }

    override func animateOneFrame() { /* The native Metal surface owns its animation clock. */ }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        scene?.stop()
        if options == nil { buildOptions() }
        // The host may retain the screensaver between repeated Options visits.
        // Always reload fixes and quality changes saved by the companion app.
        let preferences = OceanPreferences.load()
        optionsPreferences = preferences
        latitudeField.stringValue = String(format: "%.5f", preferences.coordinate.latitude)
        longitudeField.stringValue = String(format: "%.5f", preferences.coordinate.longitude)
        qualityPopup.selectItem(at: [1280, 1920, 2560].firstIndex(of: preferences.maxPixelDimension) ?? 1)
        optionsSourceLabel.stringValue = preferences.sourceDescription
        optionsStatusLabel.textColor = .systemRed
        optionsStatusLabel.stringValue = ""
        optionsStatusLabel.toolTip = nil
        return options
    }

    private func buildOptions() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 430), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Ocean"
        panel.isReleasedWhenClosed = false
        let content = NSView(frame: panel.contentView!.bounds)
        let title = NSTextField(labelWithString: "Follow the light across the sea.")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.frame = NSRect(x: 28, y: 372, width: 464, height: 28)
        let description = NSTextField(wrappingLabelWithString: "Ocean faces the Sun by day and the Moon after sunset. Your time and location align the Moon's phase, stars and Milky Way. Coordinates stay on this Mac.")
        description.frame = NSRect(x: 28, y: 311, width: 464, height: 50)
        let latitudeLabel = NSTextField(labelWithString: "Latitude")
        latitudeLabel.frame = NSRect(x: 28, y: 279, width: 210, height: 18)
        let longitudeLabel = NSTextField(labelWithString: "Longitude")
        longitudeLabel.frame = NSRect(x: 270, y: 279, width: 210, height: 18)
        latitudeField.frame = NSRect(x: 28, y: 251, width: 220, height: 24)
        longitudeField.frame = NSRect(x: 270, y: 251, width: 220, height: 24)
        latitudeField.identifier = NSUserInterfaceItemIdentifier("OceanLatitude")
        longitudeField.identifier = NSUserInterfaceItemIdentifier("OceanLongitude")
        latitudeField.setAccessibilityLabel("Latitude in degrees north")
        longitudeField.setAccessibilityLabel("Longitude in degrees east")
        for field in [latitudeField, longitudeField] {
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        let coordinateNote = NSTextField(labelWithString: "North and east are positive; south and west are negative.")
        coordinateNote.font = .systemFont(ofSize: 11)
        coordinateNote.textColor = .secondaryLabelColor
        coordinateNote.frame = NSRect(x: 28, y: 228, width: 464, height: 18)
        let settings = NSButton(title: "Use Current Location…", target: self, action: #selector(openSettings))
        settings.bezelStyle = .rounded
        settings.frame = NSRect(x: 23, y: 187, width: 210, height: 32)
        optionsSourceLabel.frame = NSRect(x: 28, y: 140, width: 464, height: 38)
        optionsSourceLabel.textColor = .secondaryLabelColor
        optionsSourceLabel.font = .systemFont(ofSize: 11)
        let qualityLabel = NSTextField(labelWithString: "Rendering")
        qualityLabel.frame = NSRect(x: 28, y: 108, width: 94, height: 20)
        qualityPopup.addItems(withTitles: ["Efficient · 1280 px", "Balanced · 1920 px", "Detailed · 2560 px"])
        qualityPopup.identifier = NSUserInterfaceItemIdentifier("OceanQuality")
        qualityPopup.frame = NSRect(x: 128, y: 104, width: 270, height: 28)
        optionsStatusLabel.frame = NSRect(x: 28, y: 64, width: 464, height: 35)
        optionsStatusLabel.identifier = NSUserInterfaceItemIdentifier("OceanOptionsStatus")
        optionsStatusLabel.font = .systemFont(ofSize: 11)
        optionsStatusLabel.textColor = .systemRed
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(closeOptions))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 313, y: 20, width: 82, height: 32)
        let save = NSButton(title: "Save", target: self, action: #selector(saveOptions))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 405, y: 20, width: 82, height: 32)
        [title, description, latitudeLabel, longitudeLabel, latitudeField, longitudeField,
         coordinateNote, settings, optionsSourceLabel, qualityLabel, qualityPopup,
         optionsStatusLabel, cancel, save].forEach { content.addSubview($0) }
        panel.contentView = content
        options = panel
    }

    @objc private func saveOptions() {
        func degrees(_ value: String) -> Double? {
            Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        }
        guard let latitude = degrees(latitudeField.stringValue), let longitude = degrees(longitudeField.stringValue) else {
            optionsStatusLabel.stringValue = "Enter latitude and longitude as numbers, for example 52.52 and 13.405."
            return
        }
        let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else {
            optionsStatusLabel.stringValue = "Latitude must be between −90° and 90°; longitude between −180° and 180°."
            return
        }
        var preferences = optionsPreferences ?? OceanPreferences.load()
        // Formatting the saved value must not turn an automatic location into a manual one.
        if abs(coordinate.latitude - preferences.coordinate.latitude) > 0.0000051 ||
            abs(coordinate.longitude - preferences.coordinate.longitude) > 0.0000051 {
            preferences.coordinateSource = .manual
            preferences.savedDate = nil
        }
        preferences.coordinate = coordinate
        preferences.maxPixelDimension = [1280, 1920, 2560][max(0, qualityPopup.indexOfSelectedItem)]
        preferences.framesPerSecond = 30
        do {
            // A plugin writes its own runtime container. The companion writes its ordinary
            // Application Support file; loading selects the newer valid document.
            try preferences.save(primaryDirectory: OceanPreferences.settingsDirectory, mirrorDirectories: [])
            optionsPreferences = preferences
            scene?.updateSun()
            closeOptions()
        } catch {
            optionsStatusLabel.stringValue = error.localizedDescription
            optionsStatusLabel.toolTip = error.localizedDescription
        }
    }

    @objc private func openSettings() {
        guard let url = Bundle(for: Self.self).url(forResource: "Ocean Settings", withExtension: "app") else {
            optionsStatusLabel.stringValue = "Ocean Settings is missing from this screensaver. Enter coordinates here, or install a fresh copy."
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--settings"]
        optionsStatusLabel.textColor = .secondaryLabelColor
        optionsStatusLabel.stringValue = "Opening Ocean Settings for location permission…"
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.optionsStatusLabel.textColor = .systemRed
                    self.optionsStatusLabel.stringValue = "Could not open Ocean Settings: " + error.localizedDescription
                    self.optionsStatusLabel.toolTip = error.localizedDescription
                } else {
                    self.closeOptions()
                }
            }
        }
    }

    private func refreshAuthorizedLocation() {
        // Only an already-authorized settings app may locate the Mac while locked.
        // Coalesce launches when the host creates a view for each display.
        guard !isPreview,
              OceanPreferences.load().coordinateSource == .current,
              Date().timeIntervalSince(Self.lastLocationRefresh) > 60,
              let url = Bundle(for: Self.self).url(forResource: "Ocean Settings", withExtension: "app") else { return }
        Self.lastLocationRefresh = Date()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--refresh-location"]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("Ocean location refresh unavailable: %@", error.localizedDescription) }
        }
    }

    @objc private func closeOptions() {
        guard let options else { return }
        options.sheetParent?.endSheet(options)
        options.orderOut(nil)
        scene?.updateSun()
        scene?.start()
    }
}
