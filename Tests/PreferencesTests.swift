import Foundation

@main
enum PreferencesTests {
    static var assertions = 0

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OceanPreferencesTests-" + UUID().uuidString,
                                                                                    isDirectory: true)
        defer {
            OceanPreferences.overrideSettingsDirectory = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("settings.json")
        OceanPreferences.overrideSettingsDirectory = directory
        check(OceanPreferences.load().coordinateSource == .timeZone, "missing settings use labelled estimate")

        let fixture = OceanPreferences(coordinate: GeographicCoordinate(latitude: -33.8688, longitude: 151.2093),
                                       coordinateSource: .current, savedDate: Date(timeIntervalSince1970: 1_700_000_000),
                                       maxPixelDimension: 2560, framesPerSecond: 30)
        try fixture.write(to: file)
        let restored = try OceanPreferences.read(from: file)
        check(restored.coordinate == fixture.coordinate, "coordinates round-trip")
        check(restored.coordinateSource == .current, "current source round-trip")
        check(restored.savedDate == fixture.savedDate, "timestamp round-trip")
        check(restored.maxPixelDimension == 2560 && restored.framesPerSecond == 30, "render settings round-trip")
        check(OceanPreferences.load().coordinate == fixture.coordinate, "explicit host directory is authoritative")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        check(permissions.intValue == 0o600, "coordinate file is private to the user")

        var manual = fixture
        manual.coordinate = GeographicCoordinate(latitude: 51.5, longitude: -0.12)
        manual.coordinateSource = .manual
        manual.savedDate = nil
        try manual.write(to: file)
        let replaced = try OceanPreferences.read(from: file)
        check(replaced.coordinate == manual.coordinate && replaced.savedDate == nil, "atomic replacement and optional date")
        let directoryContents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(directoryContents == ["settings.json"], "atomic replacement leaves only our document")

        var invalid = fixture
        invalid.coordinate = GeographicCoordinate(latitude: 91, longitude: 0)
        rejects("invalid coordinate cannot be saved") { try invalid.write(to: file) }
        try check(OceanPreferences.read(from: file).coordinate == manual.coordinate, "invalid save preserves existing document")
        invalid = fixture
        invalid.maxPixelDimension = 1_000_000
        rejects("invalid render size cannot be saved") { try invalid.write(to: file) }
        invalid = fixture
        invalid.framesPerSecond = 0
        rejects("invalid frame rate cannot be saved") { try invalid.write(to: file) }

        let invalidJSON = #"{"coordinate":{"latitude":91,"longitude":0},"coordinateSource":"manual","maxPixelDimension":1920,"framesPerSecond":30}"#
        try Data(invalidJSON.utf8).write(to: file)
        rejects("invalid JSON coordinates rejected on read") { _ = try OceanPreferences.read(from: file) }
        check(OceanPreferences.load().coordinateSource == .timeZone, "invalid document safely falls back")
        try Data("not JSON".utf8).write(to: file)
        rejects("corrupt document rejected") { _ = try OceanPreferences.read(from: file) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        rejects("unwritable target propagates error") { try fixture.write(to: blocker.appendingPathComponent("settings.json")) }

        let host = directory.appendingPathComponent("sandbox-host")
        let app = directory.appendingPathComponent("settings-app")
        let secondHost = directory.appendingPathComponent("second-host")
        try manual.save(primaryDirectory: host, mirrorDirectories: [app, secondHost, host])
        for target in [host, app, secondHost] {
            let bridged = try OceanPreferences.read(from: target.appendingPathComponent("settings.json"))
            check(bridged.coordinate == manual.coordinate && bridged.coordinateSource == .manual,
                  "settings reach each explicit host and app destination")
        }
        OceanPreferences.overrideSettingsDirectory = host
        check(OceanPreferences.load().coordinate == manual.coordinate, "host loads the mirrored location")
        rejects("partial mirror failure is surfaced") {
            try fixture.save(primaryDirectory: host, mirrorDirectories: [blocker])
        }
        try check(OceanPreferences.read(from: host.appendingPathComponent("settings.json")).coordinate == fixture.coordinate,
                  "valid primary is updated even when a mirror fails")
        rejects("primary failure is surfaced") {
            try fixture.save(primaryDirectory: blocker, mirrorDirectories: [app])
        }

        let localFile = host.appendingPathComponent("settings.json")
        let canonicalFile = app.appendingPathComponent("settings.json")
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        let later = earlier.addingTimeInterval(100)
        try manual.write(to: localFile)
        try fixture.write(to: canonicalFile)
        try FileManager.default.setAttributes([.modificationDate: earlier], ofItemAtPath: localFile.path)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: canonicalFile.path)
        check(OceanPreferences.readNewest(from: [localFile, canonicalFile])?.coordinate == fixture.coordinate,
              "newer companion location overrides older local location")
        check(OceanPreferences.load(from: [host, app]).coordinate == fixture.coordinate,
              "directory-based loading uses newest valid document")
        try FileManager.default.setAttributes([.modificationDate: later.addingTimeInterval(100)], ofItemAtPath: localFile.path)
        check(OceanPreferences.readNewest(from: [localFile, canonicalFile])?.coordinate == manual.coordinate,
              "newer native manual edit overrides companion location")
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: localFile.path)
        check(OceanPreferences.readNewest(from: [localFile, canonicalFile])?.coordinate == manual.coordinate,
              "equal timestamps prefer local native edit")
        check(OceanPreferences.readNewest(from: [canonicalFile, localFile])?.coordinate == fixture.coordinate,
              "equal timestamps preserve caller ordering")
        try Data("corrupt newer file".utf8).write(to: localFile)
        try FileManager.default.setAttributes([.modificationDate: later.addingTimeInterval(100)], ofItemAtPath: localFile.path)
        check(OceanPreferences.readNewest(from: [localFile, canonicalFile])?.coordinate == fixture.coordinate,
              "corrupt recent document does not hide valid older document")
        check(OceanPreferences.readNewest(from: [directory.appendingPathComponent("missing.json"), canonicalFile, canonicalFile])?.coordinate == fixture.coordinate,
              "missing and duplicate paths do not hide valid document")
        OceanPreferences.overrideSettingsDirectory = host
        check(OceanPreferences.load().coordinateSource == .timeZone,
              "test override never reads ordinary user settings when isolated file is corrupt")
        try manual.save()
        check(OceanPreferences.load().coordinate == manual.coordinate,
              "standard save writes injected runtime directory without mirrors")
        try check(OceanPreferences.read(from: canonicalFile).coordinate == fixture.coordinate,
                  "standard save leaves other destinations unchanged")

        let berlin = OceanPreferences.parseISO6709("+5230+01322")!
        check(abs(berlin.latitude - 52.5) < 1e-9 && abs(berlin.longitude - 13.3666666667) < 1e-8, "IANA minute precision")
        let syowa = OceanPreferences.parseISO6709("-690022+0393524")!
        check(abs(syowa.latitude + 69.0061111111) < 1e-8 && abs(syowa.longitude - 39.59) < 1e-8, "IANA second precision and hemisphere")
        for value in ["", "+90+180", "+9160+18160", "+5260+01322", "+5230+01360", "+9001+18000"] {
            check(OceanPreferences.parseISO6709(value) == nil, "invalid IANA coordinate rejected")
        }
        let cityTable = "DE\t+5230+01322\tEurope/Berlin\n"
        check(OceanPreferences.timeZoneCoordinate(timeZone: TimeZone(identifier: "Europe/Berlin")!, table: cityTable).latitude == 52.5,
              "timezone city lookup")
        check(OceanPreferences.timeZoneCoordinate(timeZone: TimeZone(secondsFromGMT: 14 * 3600)!, table: "").longitude == -150,
              "timezone meridian wraps at date line")
        print("Preferences: \(assertions) assertions passed")
    }

    static func rejects(_ message: String, _ operation: () throws -> Void) {
        do { try operation(); check(false, message) }
        catch { check(true, message) }
    }

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        assertions += 1
        if try !condition() {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
