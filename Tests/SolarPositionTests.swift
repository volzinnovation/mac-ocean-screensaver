import Foundation

@main
enum SolarPositionTests {
    static var assertions = 0

    static func main() {
        // Independent published SPA fixture: NREL/TP-560-34302, Appendix A.
        // NOAA's simpler geocentric model and standard refraction differ slightly
        // from SPA's topocentric model with site-specific pressure and temperature.
        // https://docs.nrel.gov/docs/fy08osti/34302.pdf
        let golden = position("2003-10-17T19:30:30Z", 39.742476, -105.1786)
        near(golden.azimuthDegrees, 194.34024, tolerance: 0.05, "NREL Golden azimuth")
        near(golden.apparentElevationDegrees, 90 - 50.11162, tolerance: 0.05, "NREL Golden elevation")

        // Equinox at Greenwich: near overhead at the equator, due east in the
        // morning and west in the evening. These catch azimuth quadrants/signs.
        let equinoxNoon = position("2024-03-20T12:00:00Z", 0, 0)
        check(equinoxNoon.elevationDegrees > 87, "equinox equatorial noon")
        let equinoxMorning = position("2024-03-20T06:00:00Z", 0, 0)
        let equinoxEvening = position("2024-03-20T18:00:00Z", 0, 0)
        near(equinoxMorning.azimuthDegrees, 90, tolerance: 0.5, "equinox east sunrise")
        near(equinoxEvening.azimuthDegrees, 270, tolerance: 0.5, "equinox west sunset")
        check(position("2024-03-20T00:00:00Z", 0, 0).elevationDegrees < -87, "night stays below horizon")

        // Solstice declination ±23.44° at each pole, with no unstable divisions.
        near(position("2024-06-20T20:51:00Z", 90, 0).elevationDegrees, 23.44,
             tolerance: 0.05, "north polar summer")
        near(position("2024-06-20T20:51:00Z", -90, 0).elevationDegrees, -23.44,
             tolerance: 0.05, "south polar winter")
        near(position("2024-12-21T09:20:00Z", 90, 0).elevationDegrees, -23.44,
             tolerance: 0.05, "north polar winter")
        near(position("2024-12-21T09:20:00Z", -90, 0).elevationDegrees, 23.44,
             tolerance: 0.05, "south polar summer")

        // Opposite representations of the date line must yield the same sun.
        let westDateLine = position("2024-02-29T00:01:00Z", 20, -180)
        let eastDateLine = position("2024-02-29T00:01:00Z", 20, 180)
        near(westDateLine.azimuthDegrees, eastDateLine.azimuthDegrees, tolerance: 1e-9, "date-line azimuth")
        near(westDateLine.elevationDegrees, eastDateLine.elevationDegrees, tolerance: 1e-9, "date-line elevation")

        // A single instant represented in local summer time and UTC is identical.
        let formatter = ISO8601DateFormatter()
        let berlinLocal = formatter.date(from: "2024-06-21T14:00:00+02:00")!
        let utc = formatter.date(from: "2024-06-21T12:00:00Z")!
        let berlin = GeographicCoordinate(latitude: 52.52, longitude: 13.405)
        let localPosition = SolarPosition.calculate(date: berlinLocal, coordinate: berlin)!
        let utcPosition = SolarPosition.calculate(date: utc, coordinate: berlin)!
        near(localPosition.azimuthDegrees, utcPosition.azimuthDegrees, tolerance: 1e-12, "timezone instant")
        check(localPosition.elevationDegrees > 58 && localPosition.elevationDegrees < 61, "Berlin summer altitude")

        // Nonfinite settings/date must never enter the GPU uniform bridge.
        for coordinate in [GeographicCoordinate(latitude: 91, longitude: 0),
                           GeographicCoordinate(latitude: 0, longitude: -181),
                           GeographicCoordinate(latitude: .nan, longitude: 0),
                           GeographicCoordinate(latitude: 0, longitude: .infinity)] {
            check(!coordinate.isValid, "invalid coordinate validation")
            check(SolarPosition.calculate(date: utc, coordinate: coordinate) == nil, "invalid coordinate rejection")
        }
        check(SolarPosition.calculate(date: Date(timeIntervalSince1970: .infinity), coordinate: berlin) == nil,
              "nonfinite date rejection")
        check(SolarPosition.calculate(date: Date(timeIntervalSince1970: .greatestFiniteMagnitude), coordinate: berlin) == nil,
              "overflow date rejection")

        // Sweep poles, hemisphere changes, leap day and pre-epoch UTC wrapping.
        for stamp in ["1960-02-29T00:00:00Z", "2024-02-29T23:59:59Z", "2024-06-20T20:51:00Z", "2024-12-21T09:20:00Z"] {
            for latitude in [-90.0, -89.9999, -45, 0, 45, 89.9999, 90] {
                for longitude in [-180.0, -90, 0, 90, 180] {
                    let value = position(stamp, latitude, longitude)
                    check(value.azimuthDegrees.isFinite && (0..<360).contains(value.azimuthDegrees), "finite wrapped azimuth")
                    check(value.elevationDegrees.isFinite && (-90...90).contains(value.elevationDegrees), "finite signed elevation")
                    check(value.apparentElevationDegrees.isFinite, "finite apparent elevation")
                }
            }
        }
        print("SolarPosition: \(assertions) assertions passed")
    }

    static func position(_ stamp: String, _ latitude: Double, _ longitude: Double) -> SolarPosition {
        SolarPosition.calculate(
            date: ISO8601DateFormatter().date(from: stamp)!,
            coordinate: GeographicCoordinate(latitude: latitude, longitude: longitude)
        )!
    }

    static func near(_ actual: Double, _ expected: Double, tolerance: Double, _ message: String) {
        check(abs(actual - expected) <= tolerance, "\(message): expected \(expected), got \(actual)")
    }

    static func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        }
    }
}
