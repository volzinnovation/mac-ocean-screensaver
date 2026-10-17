import AppKit
import ScreenSaver

/// Exercises native options without installing a saver or writing the user's preferences.
@main
enum ConfigureSheetTests {
    static var assertions = 0

    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OceanOptionsTests-" + UUID().uuidString,
                                                                                    isDirectory: true)
        let file = directory.appendingPathComponent("settings.json")
        OceanPreferences.overrideSettingsDirectory = directory
        defer {
            OceanPreferences.overrideSettingsDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let initial = OceanPreferences(coordinate: GeographicCoordinate(latitude: 52.52, longitude: 13.405),
                                       coordinateSource: .current, savedDate: Date(timeIntervalSince1970: 1_700_000_000),
                                       maxPixelDimension: 1920, framesPerSecond: 30)
        try initial.write(to: file)
        let saver = OceanScreenSaverView(frame: NSRect(x: 0, y: 0, width: 300, height: 200), isPreview: true)!
        check(saver.hasConfigureSheet, "native options available")
        let panel = saver.configureSheet!
        let latitude = control("OceanLatitude", in: panel) as! NSTextField
        let longitude = control("OceanLongitude", in: panel) as! NSTextField
        let quality = control("OceanQuality", in: panel) as! NSPopUpButton
        let status = control("OceanOptionsStatus", in: panel) as! NSTextField
        let save = panel.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Save" }!
        let cancel = panel.contentView!.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }!
        check(latitude.stringValue == "52.52000" && longitude.stringValue == "13.40500", "saved coordinate loaded")
        check(quality.indexOfSelectedItem == 1, "saved quality loaded")

        application.sendAction(save.action!, to: save.target, from: save)
        let unchanged = try OceanPreferences.read(from: file)
        check(unchanged.coordinateSource == .current && unchanged.savedDate == initial.savedDate,
              "saving quality preserves unchanged automatic location")

        _ = saver.configureSheet
        latitude.stringValue = "95"
        application.sendAction(save.action!, to: save.target, from: save)
        check(!status.stringValue.isEmpty, "invalid latitude shows visible validation")
        try check(OceanPreferences.read(from: file).coordinate == initial.coordinate, "invalid latitude does not change document")

        latitude.stringValue = "48,137"
        longitude.stringValue = "11.575"
        quality.selectItem(at: 2)
        application.sendAction(save.action!, to: save.target, from: save)
        let edited = try OceanPreferences.read(from: file)
        check(edited.coordinate == GeographicCoordinate(latitude: 48.137, longitude: 11.575), "manual coordinates saved")
        check(edited.coordinateSource == .manual && edited.savedDate == nil, "manual edit clears automatic source")
        check(edited.maxPixelDimension == 2560, "native quality saved")

        // Another process may have refreshed coordinates while Options was closed.
        try initial.write(to: file)
        _ = saver.configureSheet
        check(latitude.stringValue == "52.52000" && quality.indexOfSelectedItem == 1, "reopening reloads external changes")
        latitude.stringValue = "0"
        application.sendAction(cancel.action!, to: cancel.target, from: cancel)
        try check(OceanPreferences.read(from: file).coordinate == initial.coordinate, "Cancel preserves settings")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(files == ["settings.json"], "native save writes only own document in injected directory")
        print("Native configure sheet: \(assertions) assertions passed")
    }

    static func control(_ identifier: String, in window: NSWindow) -> NSView {
        window.contentView!.subviews.first { $0.identifier?.rawValue == identifier }!
    }

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        assertions += 1
        if try !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
