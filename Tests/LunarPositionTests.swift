import Foundation
import simd

@main
enum LunarPositionTests {
    private static var assertions = 0

    static func main() {
        // NASA/JPL Horizons DE441, queried 2026-10-17. Observer=coord@399,
        // SITE_COORD=(east longitude, geodetic latitude,0km), APPARENT=AIRLESS,
        // QUANTITIES=2,4,10,20,24, RANGE_UNITS=KM. Fixtures retain topocentric
        // parallax, including a Moon below the horizon and both hemispheres.
        // https://ssd-api.jpl.nasa.gov/doc/horizons.html
        // https://ssd.jpl.nasa.gov/horizons/manual.html
        let fixtures: [(String, Double, Double, Double, Double, Double, Double, Double)] = [
            ("2026-10-17T00:00:00Z", 52.52, 13.405, 277.767735, -41.789436, 0.3417045, 408895.39646, 108.4588),
            ("2026-10-25T10:00:00Z", -33.8688, 151.2093, 49.767987, 26.974671, 0.9919742, 368858.17436, 10.2746),
            ("2024-04-08T18:00:00Z", 40.7128, -74.006, 207.637538, 53.584922, 0.0000291, 354624.23609, 179.3764),
            ("2026-10-18T00:00:00Z", -0.1807, -78.4678, 214.086266, 58.253589, 0.4345732, 398548.99896, 97.5197)
        ]
        for (stamp, latitude, longitude, azimuth, elevation, illumination, distance, phase) in fixtures {
            let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
            let date = date(stamp)
            let moon = LunarPosition.calculate(date: date, coordinate: coordinate)!
            near(moon.azimuthDegrees, azimuth, tolerance: 0.003, "JPL topocentric azimuth \(stamp)")
            near(moon.elevationDegrees, elevation, tolerance: 0.003, "JPL topocentric elevation \(stamp)")
            near(moon.illuminatedFraction, illumination, tolerance: 0.00003, "JPL phase illumination \(stamp)")
            near(moon.topocentricDistanceKM, distance, tolerance: 60, "JPL observer range \(stamp)")
            near(moon.phaseAngleRadians * 180 / .pi, phase, tolerance: 0.01, "JPL Sun–Moon–observer angle \(stamp)")
            let inferredFraction = (1 - Double(simd_dot(moon.moonDirection, moon.illuminationDirection))) / 2
            near(inferredFraction, moon.illuminatedFraction, tolerance: 1e-7, "shader illumination agrees with ephemeris")
            near(Double(simd_length(moon.moonDirection)), 1, tolerance: 1e-7, "unit Moon direction")
            near(Double(simd_length(moon.sunDirection)), 1, tolerance: 1e-7, "unit Sun direction")
            near(Double(simd_length(moon.illuminationDirection)), 1, tolerance: 1e-7, "unit illumination direction")
            near(asin(Double(moon.moonDirection.y)) * 180 / .pi, elevation, tolerance: 0.003, "world direction elevation")
            near(sin(moon.angularRadiusRadians) * moon.topocentricDistanceKM, 1737.4, tolerance: 1e-9, "physical lunar angular radius")
            check((0.23...0.29).contains(moon.angularRadiusRadians * 180 / .pi), "realistic angular radius")
        }

        // Meeus chapter47 worked example, 1992-Apr-12 00:00 TT (58.184s
        // after UTC). All120 periodic terms recover the published geocentric
        // range and apparent equatorial position, without a runtime dependency.
        let exampleDate = date("1992-04-12T00:00:00Z").addingTimeInterval(-58.184)
        let example = LunarPosition.calculate(date: exampleDate, coordinate: GeographicCoordinate(latitude: 0, longitude: 0))!
        near(example.distanceKM, 368409.7, tolerance: 0.1, "Meeus geocentric lunar distance")
        near(example.rightAscensionRadians * 180 / .pi, 134.688469, tolerance: 0.0001, "Meeus apparent lunar RA")
        near(example.declinationRadians * 180 / .pi, 13.768367, tolerance: 0.0001, "Meeus apparent lunar declination")

        // Independent NASA lunar phase dates, 2024. Observer parallax slightly
        // perturbs the exact half phase, and eclipse/new Moon is never clamped.
        // https://eclipse.gsfc.nasa.gov/phase/phases2001.html
        let equator = GeographicCoordinate(latitude: 0, longitude: 0)
        let new = LunarPosition.calculate(date: date("2024-04-08T18:21:00Z"), coordinate: equator)!
        let first = LunarPosition.calculate(date: date("2024-04-15T19:13:00Z"), coordinate: equator)!
        let full = LunarPosition.calculate(date: date("2024-04-23T23:49:00Z"), coordinate: equator)!
        let last = LunarPosition.calculate(date: date("2024-05-01T11:27:00Z"), coordinate: equator)!
        check(new.illuminatedFraction < 0.0002, "NASA new Moon almost dark")
        check(full.illuminatedFraction > 0.999, "NASA full Moon almost fully illuminated")
        near(first.illuminatedFraction, 0.5, tolerance: 0.01, "NASA first quarter")
        near(last.illuminatedFraction, 0.5, tolerance: 0.01, "NASA last quarter")
        check(first.isWaxing && !last.isWaxing, "waxing/waning phases distinguish equal fractions")

        // The true celestial pole has altitude equal to geodetic latitude. This
        // independently checks ENU handedness, the world −Z=north convention,
        // and the matrix used to rotate the fixed catalog and Milky Way.
        let instant = date("2026-10-17T00:00:00Z")
        for latitude in [-90.0, -52, 0, 52, 90] {
            for longitude in [-180.0, -78, 0, 151, 180] {
                let coordinate = GeographicCoordinate(latitude: latitude, longitude: longitude)
                let frame = CelestialFrame.calculate(date: instant, coordinate: coordinate)!
                let pole = frame.localToEquatorialOfDate.transpose * SIMD3<Float>(0, 0, 1)
                near(Double(pole.x), 0, tolerance: 1e-7, "celestial pole meridian")
                near(Double(pole.y), sin(latitude * .pi / 180), tolerance: 1e-7, "celestial pole altitude")
                near(Double(pole.z), -cos(latitude * .pi / 180), tolerance: 1e-7, "celestial pole north")
                near(Double(simd_determinant(frame.localToEquatorial)), 1, tolerance: 3e-7, "J2000 transform preserves handedness")
                let ray = simd_normalize(SIMD3<Float>(0.3, 0.2, -0.8))
                let roundTrip = frame.equatorialToLocal * (frame.localToEquatorial * ray)
                near(Double(simd_length(roundTrip - ray)), 0, tolerance: 2e-7, "celestial transform round trip")
                check(frame.moon.azimuthDegrees.isFinite && frame.moon.elevationDegrees.isFinite &&
                      frame.moon.brightLimbAngleRadians.isFinite, "finite lunar angles at poles/date line")
            }
        }

        // Same physical instant has no daylight-saving or timezone dependence.
        let berlin = GeographicCoordinate(latitude: 52.52, longitude: 13.405)
        let utc = CelestialFrame.calculate(date: instant, coordinate: berlin)!
        let local = CelestialFrame.calculate(date: date("2026-10-17T02:00:00+02:00"), coordinate: berlin)!
        near(utc.moon.azimuthDegrees, local.moon.azimuthDegrees, tolerance: 1e-12, "local/UTC equivalent instant")
        check(utc.isNight && utc.viewAzimuthDegrees == utc.moon.azimuthDegrees, "night camera follows Moon")
        check(utc.moon.elevationDegrees < 0, "Moon below horizon is never lifted")
        let day = CelestialFrame.calculate(date: date("2026-10-17T11:00:00Z"), coordinate: berlin)!
        check(!day.isNight && day.viewAzimuthDegrees == day.sun.azimuthDegrees, "day camera follows Sun")
        let west = CelestialFrame.calculate(date: instant, coordinate: GeographicCoordinate(latitude: 10, longitude: -180))!
        let east = CelestialFrame.calculate(date: instant, coordinate: GeographicCoordinate(latitude: 10, longitude: 180))!
        near(west.moon.azimuthDegrees, east.moon.azimuthDegrees, tolerance: 1e-8, "date-line lunar equivalence")
        near(west.moon.elevationDegrees, east.moon.elevationDegrees, tolerance: 1e-8, "date-line altitude equivalence")

        // A sidereal day's rotation returns fixed J2000 stars to nearly the same
        // direction; a solar day's rotation instead advances about one degree.
        let siderealDay = CelestialFrame.calculate(date: instant.addingTimeInterval(86164.0905), coordinate: berlin)!
        let solarDay = CelestialFrame.calculate(date: instant.addingTimeInterval(86400), coordinate: berlin)!
        let star = SIMD3<Float>(1, 0, 0)
        let initialRay = utc.equatorialToLocal * star
        near(Double(simd_length(initialRay - siderealDay.equatorialToLocal * star)), 0, tolerance: 0.00001, "sidereal star return")
        check(simd_length(initialRay - solarDay.equatorialToLocal * star) > 0.015, "solar day advances stellar sky")

        check(LunarPosition.calculate(date: instant, coordinate: GeographicCoordinate(latitude: .nan, longitude: 0)) == nil,
              "invalid lunar coordinate rejected")
        check(LunarPosition.calculate(date: Date(timeIntervalSince1970: .infinity), coordinate: berlin) == nil,
              "nonfinite lunar date rejected")
        check(CelestialFrame.calculate(date: date("2300-01-01T00:00:00Z"), coordinate: berlin) == nil,
              "out-of-model date rejected")
        print("LunarPosition: \(assertions) assertions passed")
    }

    private static func date(_ stamp: String) -> Date { ISO8601DateFormatter().date(from: stamp)! }
    private static func near(_ actual: Double, _ expected: Double, tolerance: Double, _ message: String) {
        check(abs(actual - expected) <= tolerance, "\(message): expected \(expected), got \(actual)")
    }
    private static func check(_ condition: Bool, _ message: String) {
        assertions += 1
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
}
