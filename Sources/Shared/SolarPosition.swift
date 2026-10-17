import Foundation

/// WGS84 degrees: north and east are positive.
struct GeographicCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite &&
            (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Solar angles at sea level. Azimuth is clockwise from true north.
struct SolarPosition {
    let azimuthDegrees: Double
    /// Geometric elevation remains negative at night.
    let elevationDegrees: Double
    /// Standard-atmosphere refraction, useful for the visible solar disc.
    let apparentElevationDegrees: Double

    /// NOAA/Meeus solar geometry, evaluated at the absolute UTC instant.
    /// No timezone or daylight-saving correction is needed for a `Date`.
    /// Reference: https://gml.noaa.gov/grad/solcalc/calcdetails.html
    static func calculate(date: Date, coordinate: GeographicCoordinate) -> SolarPosition? {
        guard coordinate.isValid, date.timeIntervalSince1970.isFinite else { return nil }

        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        let centuries = (julianDay - 2451545) / 36525
        let meanLongitude = wrap(280.46646 + centuries * (36000.76983 + centuries * 0.0003032), 360)
        let meanAnomaly = radians(357.52911 + centuries * (35999.05029 - 0.0001537 * centuries))
        let eccentricity = 0.016708634 - centuries * (0.000042037 + 0.0000001267 * centuries)
        let equationOfCenter = sin(meanAnomaly) * (1.914602 - centuries * (0.004817 + 0.000014 * centuries))
            + sin(2 * meanAnomaly) * (0.019993 - 0.000101 * centuries)
            + sin(3 * meanAnomaly) * 0.000289
        let omega = radians(125.04 - 1934.136 * centuries)
        let apparentLongitude = radians(meanLongitude + equationOfCenter - 0.00569 - 0.00478 * sin(omega))
        let obliquitySeconds = 21.448 - centuries * (46.815 + centuries * (0.00059 - centuries * 0.001813))
        let obliquity = radians(23 + (26 + obliquitySeconds / 60) / 60 + 0.00256 * cos(omega))
        let declination = asin(sin(obliquity) * sin(apparentLongitude))

        let y = pow(tan(obliquity / 2), 2)
        let longitudeRadians = radians(meanLongitude)
        let equationOfTime = 4 * degrees(
            y * sin(2 * longitudeRadians) - 2 * eccentricity * sin(meanAnomaly)
                + 4 * eccentricity * y * sin(meanAnomaly) * cos(2 * longitudeRadians)
                - 0.5 * y * y * sin(4 * longitudeRadians)
                - 1.25 * eccentricity * eccentricity * sin(2 * meanAnomaly)
        )

        // Modulo the UTC epoch directly, including instants before 1970.
        let utcMinutes = wrap(date.timeIntervalSince1970, 86400) / 60
        let solarMinutes = wrap(utcMinutes + equationOfTime + 4 * coordinate.longitude, 1440)
        let hourAngle = radians(solarMinutes / 4 - 180)
        let latitude = radians(coordinate.latitude)
        let sinElevation = sin(latitude) * sin(declination)
            + cos(latitude) * cos(declination) * cos(hourAngle)
        let elevation = degrees(asin(min(1, max(-1, sinElevation))))

        // atan2 avoids divisions by sin(zenith) or cos(latitude), including poles.
        // At exact zenith/nadir azimuth is physically undefined; atan2 still yields
        // a finite direction, suitable for the renderer as elevation approaches 90°.
        let azimuth = wrap(degrees(atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latitude) - tan(declination) * cos(latitude)
        )) + 180, 360)

        guard azimuth.isFinite, elevation.isFinite else { return nil }

        return SolarPosition(
            azimuthDegrees: azimuth,
            elevationDegrees: elevation,
            apparentElevationDegrees: elevation + refraction(at: elevation)
        )
    }

    /// NOAA's standard-atmosphere approximation; no daylight clamping.
    private static func refraction(at elevation: Double) -> Double {
        if elevation > 85 { return 0 }
        let tangent = tan(radians(elevation))
        let arcseconds: Double
        if elevation > 5 {
            arcseconds = 58.1 / tangent - 0.07 / pow(tangent, 3) + 0.000086 / pow(tangent, 5)
        } else if elevation > -0.575 {
            arcseconds = 1735 + elevation * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))
        } else {
            arcseconds = -20.774 / tangent
        }
        return arcseconds / 3600
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    private static func wrap(_ value: Double, _ modulus: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }
}
