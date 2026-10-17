import AppKit
import CoreLocation

/// Location permission belongs to the companion app, never the locked-screen host.
final class SettingsWindowController: NSWindowController, NSWindowDelegate,
                                      NSTextFieldDelegate, CLLocationManagerDelegate {
    private var draft = OceanPreferences.load()
    private let latitudeField = NSTextField()
    private let longitudeField = NSTextField()
    private let qualityPopup = NSPopUpButton()
    private let locationButton = NSButton(title: "Use Current Location", target: nil, action: nil)
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let manager = CLLocationManager()
    private var locationTimeout: Timer?
    private var requestingLocation = false
    private let onSave: (() -> Void)?

    init(onSave: (() -> Void)? = nil) {
        self.onSave = onSave
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 548, height: 550),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Ocean Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        buildInterface()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true {
            draft = OceanPreferences.load()
            latitudeField.stringValue = String(format: "%.5f", draft.coordinate.latitude)
            longitudeField.stringValue = String(format: "%.5f", draft.coordinate.longitude)
            qualityPopup.selectItem(at: [1280, 1920, 2560].firstIndex(of: draft.maxPixelDimension) ?? 1)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = draft.sourceDescription
        }
        super.showWindow(sender)
    }

    private func buildInterface() {
        guard let content = window?.contentView else { return }
        let title = NSTextField(labelWithString: "An ocean at your time of day.")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString:
            "Face the Sun by day and the Moon after sunset, with its phase, stars and Milky Way aligned to your time and location.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)

        let locationTitle = NSTextField(labelWithString: "Location")
        locationTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        locationButton.target = self
        locationButton.action = #selector(useCurrentLocation)
        locationButton.bezelStyle = .rounded
        latitudeField.stringValue = String(format: "%.5f", draft.coordinate.latitude)
        longitudeField.stringValue = String(format: "%.5f", draft.coordinate.longitude)
        for field in [latitudeField, longitudeField] {
            field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            field.delegate = self
            field.widthAnchor.constraint(equalToConstant: 134).isActive = true
        }
        latitudeField.setAccessibilityLabel("Latitude, degrees north")
        longitudeField.setAccessibilityLabel("Longitude, degrees east")
        let coordinateRow = NSStackView(views: [NSTextField(labelWithString: "Latitude"), latitudeField,
                                               NSTextField(labelWithString: "Longitude"), longitudeField])
        coordinateRow.spacing = 10
        coordinateRow.alignment = .centerY
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = draft.sourceDescription
        statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 30).isActive = true
        let privacy = NSTextField(wrappingLabelWithString:
            "Coordinates stay on this Mac. Current location refreshes when the screensaver starts. Negative values mean south and west.")
        privacy.font = .systemFont(ofSize: 11)
        privacy.textColor = .secondaryLabelColor

        let qualityTitle = NSTextField(labelWithString: "Rendering")
        qualityTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        qualityPopup.addItems(withTitles: ["Efficient · 1280 px", "Balanced · 1920 px", "Detailed · 2560 px"])
        qualityPopup.selectItem(at: [1280, 1920, 2560].firstIndex(of: draft.maxPixelDimension) ?? 1)
        let qualityNote = NSTextField(labelWithString: "Maximum render size · 30 frames per second")
        qualityNote.font = .systemFont(ofSize: 11)
        qualityNote.textColor = .secondaryLabelColor
        let qualityRow = NSStackView(views: [qualityPopup, qualityNote])
        qualityRow.spacing = 12
        qualityRow.alignment = .centerY

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, cancelButton, saveButton])
        buttons.spacing = 8
        buttons.alignment = .centerY

        let stack = NSStackView(views: [title, subtitle, gap(9), locationTitle, locationButton,
                                      coordinateRow, statusLabel, privacy, gap(8), qualityTitle,
                                      qualityRow, gap(10), buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            privacy.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func gap(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    func controlTextDidChange(_ notification: Notification) {
        stopLocationRequest()
        draft.coordinateSource = .manual
        draft.savedDate = nil
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Manual coordinates. Select Save to apply."
    }

    @objc private func saveSettings() {
        guard let latitude = parseDegrees(latitudeField.stringValue),
              let longitude = parseDegrees(longitudeField.stringValue) else {
            showError("Enter latitude and longitude as numbers, for example 52.52 and 13.405.")
            return
        }
        let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else {
            showError("Latitude must be between −90° and 90°; longitude between −180° and 180°.")
            return
        }
        stopLocationRequest()
        draft.coordinate = coordinate
        draft.maxPixelDimension = [1280, 1920, 2560][max(0, qualityPopup.indexOfSelectedItem)]
        draft.framesPerSecond = 30
        do {
            try draft.save()
            onSave?()
            close()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Ocean settings could not be fully saved"
            if let window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
        }
    }

    private func parseDegrees(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    @objc private func cancel() {
        stopLocationRequest()
        close()
    }

    @objc private func useCurrentLocation() {
        guard !requestingLocation else { return }
        guard CLLocationManager.locationServicesEnabled() else {
            showError("Location Services is off. Enable it in System Settings → Privacy & Security, or enter coordinates manually.")
            return
        }
        requestingLocation = true
        locationButton.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Finding your location…"
        locationTimeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
            self?.stopLocationRequest()
            self?.showError("Location timed out. Try again with Wi-Fi enabled, or enter coordinates manually.")
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            locationDenied()
        @unknown default:
            locationDenied()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestingLocation else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            locationDenied()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requestingLocation,
              let location = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 600 }) else { return }
        let coordinate = GeographicCoordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        guard coordinate.isValid else { return }
        stopLocationRequest()
        draft.coordinate = coordinate
        draft.coordinateSource = .current
        draft.savedDate = Date()
        latitudeField.stringValue = String(format: "%.5f", coordinate.latitude)
        longitudeField.stringValue = String(format: "%.5f", coordinate.longitude)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Location found. Select Save to apply."
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard requestingLocation else { return }
        stopLocationRequest()
        if let locationError = error as? CLError, locationError.code == .denied {
            locationDenied()
        } else {
            showError("Could not find your location. Check Wi-Fi and Location Services, or enter coordinates manually.")
        }
    }

    private func locationDenied() {
        stopLocationRequest()
        showError("Location access was denied. Allow Ocean Settings in System Settings → Privacy & Security → Location Services, or enter coordinates manually.")
    }

    private func stopLocationRequest() {
        requestingLocation = false
        locationTimeout?.invalidate()
        locationTimeout = nil
        manager.stopUpdatingLocation()
        locationButton.isEnabled = true
    }

    private func showError(_ message: String) {
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
    }

    func windowWillClose(_ notification: Notification) { stopLocationRequest() }
}
