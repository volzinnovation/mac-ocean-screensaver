import Foundation
import Darwin

/// An app-owned JSON document bridges the settings app and sandboxed ScreenSaver host.
struct OceanPreferences: Codable {
    static let moduleIdentifier = "com.noniv.OceanScreenSaver"
    static let changedNotification = Notification.Name(moduleIdentifier + ".settingsChanged")

    enum CoordinateSource: String, Codable {
        case current, manual, timeZone
    }

    var coordinate: GeographicCoordinate
    var coordinateSource: CoordinateSource
    var savedDate: Date?
    var maxPixelDimension: Int = 1920
    var framesPerSecond: Int = 30

    var sourceDescription: String {
        switch coordinateSource {
        case .current:
            if let savedDate {
                return "Current location, saved " + savedDate.formatted(date: .abbreviated, time: .shortened)
            }
            return "Saved current location"
        case .manual:
            return "Manual coordinates"
        case .timeZone:
            return "Approximate location from your time zone (" + TimeZone.current.identifier + ")"
        }
    }

    /// Tests can isolate all reads and writes from the user's actual settings.
    static var overrideSettingsDirectory: URL?

    static var settingsDirectory: URL {
        overrideSettingsDirectory ?? runtimeSettingsDirectory
    }

    private static var runtimeSettingsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("OceanScreenSaver", isDirectory: true)
    }

    private static var canonicalSettingsDirectory: URL {
        // Foundation's home/application-support APIs resolve into the container in a
        // sandboxed host. The account database retains the actual user's home path.
        let realHome: URL
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            realHome = URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        } else {
            realHome = FileManager.default.homeDirectoryForCurrentUser
        }
        return realHome
            .appendingPathComponent("Library/Application Support/OceanScreenSaver", isDirectory: true)
    }

    static func load() -> OceanPreferences {
        let directories: [URL]
        if let overrideSettingsDirectory { directories = [overrideSettingsDirectory] }
        else { directories = [runtimeSettingsDirectory, canonicalSettingsDirectory] }
        return load(from: directories)
    }

    static func load(from directories: [URL]) -> OceanPreferences {
        let fallback = OceanPreferences(coordinate: timeZoneCoordinate(), coordinateSource: .timeZone)
        let files = directories.map { $0.appendingPathComponent("settings.json") }
        guard var stored = readNewest(from: files) else { return fallback }
        // An estimate follows the current system timezone rather than a formerly saved city.
        if stored.coordinateSource == .timeZone { stored.coordinate = timeZoneCoordinate() }
        return stored
    }

    /// First URL wins equal timestamps, allowing the saver to prefer its local edits.
    /// Corrupt, inaccessible and missing documents never hide a valid older document.
    static func readNewest(from fileURLs: [URL]) -> OceanPreferences? {
        var selected: OceanPreferences?
        var selectedDate = Date.distantPast
        var visited = Set<String>()
        for fileURL in fileURLs {
            let normalized = fileURL.standardizedFileURL
            guard visited.insert(normalized.path).inserted,
                  let preferences = try? read(from: normalized),
                  let values = try? normalized.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modifiedDate = values.contentModificationDate else { continue }
            if selected == nil || modifiedDate > selectedDate {
                selected = preferences
                selectedDate = modifiedDate
            }
        }
        return selected
    }

    /// Pure file access for tests and explicit imports. Invalid documents never reach the renderer.
    static func read(from fileURL: URL) throws -> OceanPreferences {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let preferences = try decoder.decode(OceanPreferences.self, from: Data(contentsOf: fileURL))
        try preferences.validate()
        return preferences
    }

    /// Writes only our own settings document; never mutates the host's preferences.
    func write(to fileURL: URL) throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = try encoder.encode(self)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try document.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func save() throws {
        // The companion writes only its own ordinary Application Support document.
        // It must never access Apple's protected ScreenSaver containers, especially
        // during a headless location refresh where a privacy prompt would be disruptive.
        try save(primaryDirectory: Self.settingsDirectory, mirrorDirectories: [])
    }

    /// Explicit destinations allow isolated tests and deliberate imports without user-data writes.
    func save(primaryDirectory: URL, mirrorDirectories: [URL]) throws {
        let primary = primaryDirectory.standardizedFileURL
        do {
            try write(to: primary.appendingPathComponent("settings.json"))
        } catch {
            throw StorageError.writeFailed(primary.path, error.localizedDescription)
        }
        var failures: [String] = []
        var written = Set([primary.path])
        // No production caller supplies mirrors. Keep explicit destinations useful
        // for testing partial-write errors and for deliberate, user-directed exports.
        for directory in mirrorDirectories {
            let normalized = directory.standardizedFileURL
            guard written.insert(normalized.path).inserted else { continue }
            do { try write(to: normalized.appendingPathComponent("settings.json")) }
            catch { failures.append(normalized.path + ": " + error.localizedDescription) }
        }
        // Successful primary writes must still reach previews when another mirror failed.
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
        if !failures.isEmpty { throw StorageError.partialSave(failures) }
    }

    private func validate() throws {
        guard coordinate.isValid,
              [1280, 1920, 2560].contains(maxPixelDimension),
              [24, 30, 60].contains(framesPerSecond),
              savedDate?.timeIntervalSince1970.isFinite != false else {
            throw StorageError.invalidDocument
        }
    }

    enum StorageError: LocalizedError {
        case invalidDocument
        case writeFailed(String, String)
        case partialSave([String])

        var errorDescription: String? {
            switch self {
            case .invalidDocument:
                return "The Ocean settings document contains invalid coordinates or rendering values."
            case let .writeFailed(directory, reason):
                return "Could not save Ocean settings in \(directory): \(reason)"
            case let .partialSave(failures):
                return "Settings were saved, but could not be copied to every requested destination. " + failures.joined(separator: "\n")
            }
        }
    }

    /// IANA's public-domain table locates the representative city, not the user.
    /// This only supplies an explicitly labelled estimate before location is configured.
    static func timeZoneCoordinate(timeZone: TimeZone = .current, table: String? = nil) -> GeographicCoordinate {
        let zoneTable = table ?? (try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) ?? ""
        for line in zoneTable.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, String(fields[2]) == timeZone.identifier,
                  let coordinate = parseISO6709(String(fields[1])) else { continue }
            return coordinate
        }
        // Time zones without a named city still have a useful estimated solar meridian.
        // Use winter's standard GMT offset, avoiding an extra hour due to daylight saving.
        let offset = Double(timeZone.secondsFromGMT()) - timeZone.daylightSavingTimeOffset()
        let meridian = offset / 240
        let longitude = (meridian + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeographicCoordinate(latitude: 0, longitude: longitude)
    }

    static func parseISO6709(_ text: String) -> GeographicCoordinate? {
        let characters = Array(text)
        guard characters.first == "+" || characters.first == "-",
              let split = characters.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func component(_ part: ArraySlice<Character>, degreeDigits: Int) -> Double? {
            let value = Array(part)
            guard value.count == degreeDigits + 3 || value.count == degreeDigits + 5,
                  value.first == "+" || value.first == "-" else { return nil }
            guard let degrees = Double(String(value[1...degreeDigits])),
                  let minutes = Double(String(value[(degreeDigits + 1)...(degreeDigits + 2)])),
                  minutes < 60 else { return nil }
            var seconds = 0.0
            if value.count == degreeDigits + 5 {
                guard let parsed = Double(String(value[(degreeDigits + 3)...(degreeDigits + 4)])), parsed < 60 else { return nil }
                seconds = parsed
            }
            return (value[0] == "-" ? -1 : 1) * (degrees + minutes / 60 + seconds / 3600)
        }
        guard let latitude = component(characters[..<split], degreeDigits: 2),
              let longitude = component(characters[split...], degreeDigits: 3) else { return nil }
        let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }
}
