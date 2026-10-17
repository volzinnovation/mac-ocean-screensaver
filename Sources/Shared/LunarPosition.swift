import Foundation
import simd

/// Topocentric Moon at sea level. Angles use true north; the geometric centre
/// remains below the horizon when the Moon has not risen or has already set.
struct LunarPosition {
    let azimuthDegrees: Double
    let elevationDegrees: Double
    /// Apparent, geocentric equatorial coordinates referred to the equinox of date.
    let rightAscensionRadians: Double
    let declinationRadians: Double
    let distanceKM: Double
    let topocentricDistanceKM: Double
    let illuminatedFraction: Double
    /// Sun–Moon–observer angle: zero at full Moon, pi at new Moon.
    let phaseAngleRadians: Double
    let angularRadiusRadians: Double
    let brightLimbAngleRadians: Double
    let isWaxing: Bool
    /// World coordinates throughout: +X east, +Y zenith, −Z true north.
    let sunDirection: SIMD3<Float>
    let moonDirection: SIMD3<Float>
    /// Direction from the Moon toward the Sun, for a correctly rotated terminator.
    let illuminationDirection: SIMD3<Float>

    static func calculate(date: Date, coordinate: GeographicCoordinate) -> LunarPosition? {
        guard let geometry = LunarGeometry(date: date, coordinate: coordinate) else { return nil }
        return geometry.moon
    }
}

/// One consistent astronomical frame for the sea, Moon, catalog stars and galaxy.
struct CelestialFrame {
    let sun: SolarPosition
    let moon: LunarPosition
    let localSiderealRadians: Double
    /// Maps a local world ray into J2000 equatorial Cartesian coordinates. This
    /// includes precession/nutation so fixed J2000 star/galactic data stay aligned.
    let localToEquatorial: simd_float3x3
    /// Maps local world rays into the true equatorial frame of the current date.
    let localToEquatorialOfDate: simd_float3x3

    var equatorialToLocal: simd_float3x3 { localToEquatorial.transpose }
    /// Standard sunset: the solar upper limb has left the refracted horizon.
    var isNight: Bool { sun.elevationDegrees < -0.833 }
    var viewAzimuthDegrees: Double { isNight ? moon.azimuthDegrees : sun.azimuthDegrees }

    static func calculate(date: Date, coordinate: GeographicCoordinate) -> CelestialFrame? {
        guard let sun = SolarPosition.calculate(date: date, coordinate: coordinate),
              let geometry = LunarGeometry(date: date, coordinate: coordinate) else { return nil }
        return CelestialFrame(sun: sun, moon: geometry.moon,
                              localSiderealRadians: geometry.sidereal,
                              localToEquatorial: floatMatrix(geometry.localToJ2000),
                              localToEquatorialOfDate: floatMatrix(geometry.localToOfDate))
    }

    private static func floatMatrix(_ matrix: simd_double3x3) -> simd_float3x3 {
        simd_float3x3(columns: (SIMD3<Float>(matrix[0]), SIMD3<Float>(matrix[1]), SIMD3<Float>(matrix[2])))
    }
}

/// Independent implementation of Meeus, Astronomical Algorithms, chapters 21,
/// 22, 40, 47 and 48. The numerical periodic coefficients below are tables
/// 47.A/47.B, with all 60 longitude/range and all 60 latitude terms retained.
/// The model is intended for the current era (1800–2200), not navigation.
private struct LunarGeometry {
    let moon: LunarPosition
    let sidereal: Double
    let localToOfDate: simd_double3x3
    let localToJ2000: simd_double3x3

    init?(date: Date, coordinate: GeographicCoordinate) {
        guard coordinate.isValid, date.timeIntervalSince1970.isFinite else { return nil }
        let jdUTC = date.timeIntervalSince1970 / 86400 + 2440587.5
        guard (2378496.5...2524593.5).contains(jdUTC) else { return nil }
        let jdTT = jdUTC + Self.terrestrialOffset(date: date) / 86400
        let t = (jdTT - 2451545) / 36525
        let t2 = t * t, t3 = t2 * t, t4 = t3 * t
        let longitudeMean = Self.radians(218.3164477 + 481267.88123421 * t - 0.0015786 * t2 + t3 / 538841 - t4 / 65194000)
        let elongation = Self.radians(297.8501921 + 445267.1114034 * t - 0.0018819 * t2 + t3 / 545868 - t4 / 113065000)
        let solarAnomaly = Self.radians(357.5291092 + 35999.0502909 * t - 0.0001536 * t2 + t3 / 24490000)
        let lunarAnomaly = Self.radians(134.9633964 + 477198.8675055 * t + 0.0087414 * t2 + t3 / 69699 - t4 / 14712000)
        let latitudeArgument = Self.radians(93.2720950 + 483202.0175233 * t - 0.0036539 * t2 - t3 / 3526000 + t4 / 863310000)
        let eccentricity = 1 - 0.002516 * t - 0.0000074 * t2
        let arguments = SIMD4(elongation, solarAnomaly, lunarAnomaly, latitudeArgument)
        var longitudeSum = 0.0, distanceSum = 0.0, latitudeSum = 0.0
        for term in Self.longitudeTerms {
            let angle = simd_dot(term.arguments, arguments)
            let factor = pow(eccentricity, abs(term.arguments.y))
            longitudeSum += term.longitude * factor * sin(angle)
            distanceSum += term.distance * factor * cos(angle)
        }
        for term in Self.latitudeTerms {
            let angle = simd_dot(term.arguments, arguments)
            latitudeSum += term.latitude * pow(eccentricity, abs(term.arguments.y)) * sin(angle)
        }
        let a1 = Self.radians(119.75 + 131.849 * t)
        let a2 = Self.radians(53.09 + 479264.290 * t)
        let a3 = Self.radians(313.45 + 481266.484 * t)
        longitudeSum += 3958 * sin(a1) + 1962 * sin(longitudeMean - latitudeArgument) + 318 * sin(a2)
        latitudeSum += -2235 * sin(longitudeMean) + 382 * sin(a3)
            + 175 * sin(a1 - latitudeArgument) + 175 * sin(a1 + latitudeArgument)
            + 127 * sin(longitudeMean - lunarAnomaly) - 115 * sin(longitudeMean + lunarAnomaly)
        let lunarLongitude = longitudeMean + Self.radians(longitudeSum / 1e6)
        let lunarLatitude = Self.radians(latitudeSum / 1e6)
        let lunarDistance = 385000.56 + distanceSum / 1000

        let solarLongitudeMean = Self.radians(280.46646 + 36000.76983 * t + 0.0003032 * t2)
        let node = Self.radians(125.04452 - 1934.136261 * t + 0.0020708 * t2 + t3 / 450000)
        // Dominant nutation terms: sub-arcsecond accuracy suffices for this model.
        let deltaPsi = Self.radians((-17.20 * sin(node) - 1.32 * sin(2 * solarLongitudeMean)
            - 0.23 * sin(2 * longitudeMean) + 0.21 * sin(2 * node)) / 3600)
        let deltaEpsilon = Self.radians((9.20 * cos(node) + 0.57 * cos(2 * solarLongitudeMean)
            + 0.10 * cos(2 * longitudeMean) - 0.09 * cos(2 * node)) / 3600)
        let epsilonMean = Self.radians(23 + (26 + (21.448 - 46.8150 * t - 0.00059 * t2 + 0.001813 * t3) / 60) / 60)
        let epsilon = epsilonMean + deltaEpsilon
        let eclipticToEquatorial = Self.rotationX(epsilon)
        let lunarUnit = eclipticToEquatorial * Self.spherical(longitude: lunarLongitude + deltaPsi, latitude: lunarLatitude)
        let ra = Self.wrap(atan2(lunarUnit.y, lunarUnit.x))
        let dec = asin(Self.clamp(lunarUnit.z))
        let lunarEquatorial = lunarUnit * lunarDistance

        // Low-order solar orbit, consistent with the NOAA solar calculation.
        let solarCentre = Self.radians((1.914602 - 0.004817 * t - 0.000014 * t2) * sin(solarAnomaly)
            + (0.019993 - 0.000101 * t) * sin(2 * solarAnomaly) + 0.000289 * sin(3 * solarAnomaly))
        let solarTrueLongitude = solarLongitudeMean + solarCentre
        let solarApparentLongitude = solarTrueLongitude + deltaPsi - Self.radians(20.4898 / 3600)
        let solarEccentricity = 0.016708634 - 0.000042037 * t - 0.0000001267 * t2
        let solarRadiusAU = 1.000001018 * (1 - solarEccentricity * solarEccentricity)
            / (1 + solarEccentricity * cos(solarAnomaly + solarCentre))
        let solarUnit = eclipticToEquatorial * Self.spherical(longitude: solarApparentLongitude, latitude: 0)
        let solarEquatorial = solarUnit * (solarRadiusAU * 149597870.7)

        let tu = (jdUTC - 2451545) / 36525
        let greenwich = Self.radians(280.46061837 + 360.98564736629 * (jdUTC - 2451545)
            + 0.000387933 * tu * tu - tu * tu * tu / 38710000) + deltaPsi * cos(epsilon)
        sidereal = Self.wrap(greenwich + Self.radians(coordinate.longitude))
        let phi = Self.radians(coordinate.latitude)
        let east = SIMD3(-sin(sidereal), cos(sidereal), 0)
        let up = SIMD3(cos(phi) * cos(sidereal), cos(phi) * sin(sidereal), sin(phi))
        let south = SIMD3(sin(phi) * cos(sidereal), sin(phi) * sin(sidereal), -cos(phi))
        localToOfDate = simd_double3x3(columns: (east, up, south))
        let dateToLocal = localToOfDate.transpose

        // WGS84 ellipsoidal observer at sea level. Vector subtraction handles
        // lunar parallax without a pole/zenith division or an altitude shortcut.
        let flattening = 1 / 298.257223563
        let e2 = flattening * (2 - flattening)
        let n = 6378.137 / sqrt(1 - e2 * sin(phi) * sin(phi))
        let observer = SIMD3(n * cos(phi) * cos(sidereal), n * cos(phi) * sin(sidereal), n * (1 - e2) * sin(phi))
        let topocentricMoon = lunarEquatorial - observer
        let observerDistance = simd_length(topocentricMoon)
        let localMoon = simd_normalize(dateToLocal * topocentricMoon)
        let localSun = simd_normalize(dateToLocal * solarEquatorial)
        let localLight = simd_normalize(dateToLocal * (solarEquatorial - lunarEquatorial))
        let phaseCosine = Self.clamp(simd_dot(simd_normalize(solarEquatorial - lunarEquatorial),
                                                    simd_normalize(observer - lunarEquatorial)))
        let sunRA = atan2(solarUnit.y, solarUnit.x), sunDec = asin(Self.clamp(solarUnit.z))
        let limbAngle = atan2(cos(sunDec) * sin(sunRA - ra),
                              sin(sunDec) * cos(dec) - cos(sunDec) * sin(dec) * cos(sunRA - ra))
        let azimuth = Self.wrap(atan2(localMoon.x, -localMoon.z)) * 180 / .pi
        let elevation = asin(Self.clamp(localMoon.y)) * 180 / .pi
        guard azimuth.isFinite, elevation.isFinite, observerDistance.isFinite else { return nil }
        moon = LunarPosition(azimuthDegrees: azimuth, elevationDegrees: elevation,
                             rightAscensionRadians: ra, declinationRadians: dec,
                             distanceKM: lunarDistance, topocentricDistanceKM: observerDistance,
                             illuminatedFraction: (1 + phaseCosine) / 2,
                             phaseAngleRadians: acos(phaseCosine),
                             angularRadiusRadians: asin(1737.4 / observerDistance),
                             brightLimbAngleRadians: limbAngle,
                             isWaxing: Self.wrap(lunarLongitude - solarTrueLongitude) < .pi,
                             sunDirection: SIMD3<Float>(localSun), moonDirection: SIMD3<Float>(localMoon),
                             illuminationDirection: SIMD3<Float>(localLight))

        // J2000 -> mean equator of date -> true equator of date.
        let zeta = Self.radians((2306.2181 * t + 0.30188 * t2 + 0.017998 * t3) / 3600)
        let z = Self.radians((2306.2181 * t + 1.09468 * t2 + 0.018203 * t3) / 3600)
        let theta = Self.radians((2004.3109 * t - 0.42665 * t2 - 0.041833 * t3) / 3600)
        let precession = Self.rotationZ(z) * Self.rotationY(-theta) * Self.rotationZ(zeta)
        let nutation = Self.rotationX(epsilon) * Self.rotationZ(deltaPsi) * Self.rotationX(-epsilonMean)
        localToJ2000 = (nutation * precession).transpose * localToOfDate
    }

    private static func spherical(longitude: Double, latitude: Double) -> SIMD3<Double> {
        SIMD3(cos(latitude) * cos(longitude), cos(latitude) * sin(longitude), sin(latitude))
    }
    private static func radians(_ value: Double) -> Double { value * .pi / 180 }
    private static func clamp(_ value: Double) -> Double { min(1, max(-1, value)) }
    private static func wrap(_ value: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: 2 * .pi)
        return result < 0 ? result + 2 * .pi : result
    }
    private static func rotationX(_ angle: Double) -> simd_double3x3 {
        simd_double3x3(columns: (SIMD3(1, 0, 0), SIMD3(0, cos(angle), sin(angle)), SIMD3(0, -sin(angle), cos(angle))))
    }
    private static func rotationY(_ angle: Double) -> simd_double3x3 {
        simd_double3x3(columns: (SIMD3(cos(angle), 0, -sin(angle)), SIMD3(0, 1, 0), SIMD3(sin(angle), 0, cos(angle))))
    }
    private static func rotationZ(_ angle: Double) -> simd_double3x3 {
        simd_double3x3(columns: (SIMD3(cos(angle), sin(angle), 0), SIMD3(-sin(angle), cos(angle), 0), SIMD3(0, 0, 1)))
    }

    private static func terrestrialOffset(date: Date) -> Double {
        // UTC leap seconds through 2017 (37 TAI−UTC). Future leap seconds alter
        // lunar geometry by about half an arcsecond each, immaterial visually.
        let seconds = date.timeIntervalSince1970
        let leapEpochs: [(Double, Double)] = [
            (1483228800, 37), (1435708800, 36), (1341100800, 35), (1230768000, 34),
            (1136073600, 33), (915148800, 32), (867715200, 31), (820454400, 30),
            (773020800, 29), (741484800, 28), (709948800, 27), (662688000, 26),
            (631152000, 25), (567993600, 24), (489024000, 23), (425865600, 22),
            (394329600, 21), (362793600, 20), (315532800, 19), (283996800, 18),
            (252460800, 17), (220924800, 16), (189302400, 15), (157766400, 14),
            (126230400, 13), (94694400, 12), (78796800, 11), (63072000, 10)
        ]
        if let offset = leapEpochs.first(where: { seconds >= $0.0 }) { return offset.1 + 32.184 }
        // Before atomic UTC, use the historical TT−UT polynomial approximation.
        // NASA: https://eclipse.gsfc.nasa.gov/SEcat5/deltatpoly.html
        let year = 1970 + seconds / (365.2425 * 86400)
        if year >= 1961 {
            let x = year - 1975
            return 45.45 + 1.067 * x - x * x / 260 - x * x * x / 718
        }
        if year >= 1941 {
            let x = year - 1950
            return 29.07 + 0.407 * x - x * x / 233 + x * x * x / 2547
        }
        if year >= 1920 {
            let x = year - 1920
            return 21.20 + 0.84493 * x - 0.076100 * x * x + 0.0020936 * x * x * x
        }
        if year >= 1900 {
            let x = year - 1900
            return -2.79 + 1.494119 * x - 0.0598939 * pow(x, 2) + 0.0061966 * pow(x, 3) - 0.000197 * pow(x, 4)
        }
        let x = year - 1860
        if year >= 1860 { return 7.62 + 0.5737 * x - 0.251754 * x * x + 0.01680668 * pow(x, 3) - 0.0004473624 * pow(x, 4) + pow(x, 5) / 233174 }
        let u = year - 1800
        return 13.72 - 0.332447 * u + 0.0068612 * pow(u, 2) + 0.0041116 * pow(u, 3)
            - 0.00037436 * pow(u, 4) + 0.0000121272 * pow(u, 5) - 0.0000001699 * pow(u, 6) + 0.000000000875 * pow(u, 7)
    }

    private struct LongitudeTerm {
        let arguments: SIMD4<Double>
        let longitude: Double
        let distance: Double
        init(_ d: Double, _ m: Double, _ p: Double, _ f: Double, _ l: Double, _ r: Double) {
            arguments = SIMD4(d, m, p, f); longitude = l; distance = r
        }
    }
    private struct LatitudeTerm {
        let arguments: SIMD4<Double>
        let latitude: Double
        init(_ d: Double, _ m: Double, _ p: Double, _ f: Double, _ b: Double) {
            arguments = SIMD4(d, m, p, f); latitude = b
        }
    }
    private static let longitudeTerms: [LongitudeTerm] = [
        .init(0,0,1,0,6288774,-20905355), .init(2,0,-1,0,1274027,-3699111),
        .init(2,0,0,0,658314,-2955968), .init(0,0,2,0,213618,-569925),
        .init(0,1,0,0,-185116,48888), .init(0,0,0,2,-114332,-3149),
        .init(2,0,-2,0,58793,246158), .init(2,-1,-1,0,57066,-152138),
        .init(2,0,1,0,53322,-170733), .init(2,-1,0,0,45758,-204586),
        .init(0,1,-1,0,-40923,-129620), .init(1,0,0,0,-34720,108743),
        .init(0,1,1,0,-30383,104755), .init(2,0,0,-2,15327,10321),
        .init(0,0,1,2,-12528,0), .init(0,0,1,-2,10980,79661),
        .init(4,0,-1,0,10675,-34782), .init(0,0,3,0,10034,-23210),
        .init(4,0,-2,0,8548,-21636), .init(2,1,-1,0,-7888,24208),
        .init(2,1,0,0,-6766,30824), .init(1,0,-1,0,-5163,-8379),
        .init(1,1,0,0,4987,-16675), .init(2,-1,1,0,4036,-12831),
        .init(2,0,2,0,3994,-10445), .init(4,0,0,0,3861,-11650),
        .init(2,0,-3,0,3665,14403), .init(0,1,-2,0,-2689,-7003),
        .init(2,0,-1,2,-2602,0), .init(2,-1,-2,0,2390,10056),
        .init(1,0,1,0,-2348,6322), .init(2,-2,0,0,2236,-9884),
        .init(0,1,2,0,-2120,5751), .init(0,2,0,0,-2069,0),
        .init(2,-2,-1,0,2048,-4950), .init(2,0,1,-2,-1773,4130),
        .init(2,0,0,2,-1595,0), .init(4,-1,-1,0,1215,-3958),
        .init(0,0,2,2,-1110,0), .init(3,0,-1,0,-892,3258),
        .init(2,1,1,0,-810,2616), .init(4,-1,-2,0,759,-1897),
        .init(0,2,-1,0,-713,-2117), .init(2,2,-1,0,-700,2354),
        .init(2,1,-2,0,691,0), .init(2,-1,0,-2,596,0),
        .init(4,0,1,0,549,-1423), .init(0,0,4,0,537,-1117),
        .init(4,-1,0,0,520,-1571), .init(1,0,-2,0,-487,-1739),
        .init(2,1,0,-2,-399,0), .init(0,0,2,-2,-381,-4421),
        .init(1,1,1,0,351,0), .init(3,0,-2,0,-340,0),
        .init(4,0,-3,0,330,0), .init(2,-1,2,0,327,0),
        .init(0,2,1,0,-323,1165), .init(1,1,-1,0,299,0),
        .init(2,0,3,0,294,0), .init(2,0,-1,-2,0,8752)
    ]
    private static let latitudeTerms: [LatitudeTerm] = [
        .init(0,0,0,1,5128122), .init(0,0,1,1,280602), .init(0,0,1,-1,277693),
        .init(2,0,0,-1,173237), .init(2,0,-1,1,55413), .init(2,0,-1,-1,46271),
        .init(2,0,0,1,32573), .init(0,0,2,1,17198), .init(2,0,1,-1,9266),
        .init(0,0,2,-1,8822), .init(2,-1,0,-1,8216), .init(2,0,-2,-1,4324),
        .init(2,0,1,1,4200), .init(2,1,0,-1,-3359), .init(2,-1,-1,1,2463),
        .init(2,-1,0,1,2211), .init(2,-1,-1,-1,2065), .init(0,1,-1,-1,-1870),
        .init(4,0,-1,-1,1828), .init(0,1,0,1,-1794), .init(0,0,0,3,-1749),
        .init(0,1,-1,1,-1565), .init(1,0,0,1,-1491), .init(0,1,1,1,-1475),
        .init(0,1,1,-1,-1410), .init(0,1,0,-1,-1344), .init(1,0,0,-1,-1335),
        .init(0,0,3,1,1107), .init(4,0,0,-1,1021), .init(4,0,-1,1,833),
        .init(0,0,1,-3,777), .init(4,0,-2,1,671), .init(2,0,0,-3,607),
        .init(2,0,2,-1,596), .init(2,-1,1,-1,491), .init(2,0,-2,1,-451),
        .init(0,0,3,-1,439), .init(2,0,2,1,422), .init(2,0,-3,-1,421),
        .init(2,1,-1,1,-366), .init(2,1,0,1,-351), .init(4,0,0,1,331),
        .init(2,-1,1,1,315), .init(2,-2,0,-1,302), .init(0,0,1,3,-283),
        .init(2,1,1,-1,-229), .init(1,1,0,-1,223), .init(1,1,0,1,223),
        .init(0,1,-2,-1,-220), .init(2,1,-1,-1,-220), .init(1,0,1,1,-185),
        .init(2,-1,-2,-1,181), .init(0,1,2,1,-177), .init(4,0,-2,-1,176),
        .init(4,-1,-1,-1,166), .init(1,0,1,-1,-164), .init(4,0,1,-1,132),
        .init(1,0,-1,-1,-119), .init(4,-1,0,-1,115), .init(2,-2,0,1,107)
    ]
}
