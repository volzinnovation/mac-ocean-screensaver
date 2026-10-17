import Foundation
import simd

/// The shader's eight aligned vec4 values. Equatorial atlas axes deliberately use
/// X=RA0, Y=north celestial pole, Z=RA6h, unlike the standard astronomy XYZ frame.
struct CelestialUniforms {
    let values: [Float]
    let exposure: Float

    init(frame: CelestialFrame) {
        let moon = frame.moon
        let stars = Self.fade(-5, -18, frame.sun.elevationDegrees)
        let adaptation = Self.fade(-2, -14, frame.sun.elevationDegrees)
        let moonAboveHorizon = Self.fade(-0.3, 8, moon.elevationDegrees)
        let moonGlare = moon.illuminatedFraction * moonAboveHorizon
        let previousExposure = 1.35 * (1 + 47 * adaptation)
        let adaptedExposure = 1.35 * pow(1000, adaptation)
        exposure = Float(adaptedExposure)
        var data = [Float](repeating: 0, count: 32)
        func vector(_ direction: SIMD3<Float>, _ fourth: Float, at index: Int) {
            data[index] = direction.x; data[index + 1] = direction.y
            data[index + 2] = direction.z; data[index + 3] = fourth
        }
        vector(moon.moonDirection, Float(moon.angularRadiusRadians), at: 0)
        vector(moon.illuminationDirection, Float(moon.illuminatedFraction), at: 4)
        let matrix = frame.localToEquatorial
        for (destination, row) in [(8, 0), (12, 2), (16, 1)] {
            vector(SIMD3(matrix[0][row], matrix[1][row], matrix[2][row]), 0, at: destination)
        }
        data[20] = Float(stars)
        data[21] = 0.6 // Lunar surface radiance; adapt exposure, never enlarge the disc.
        data[22] = Float(0.015 * previousExposure / adaptedExposure * (1 - 0.85 * moonGlare))
        data[23] = Float(0.0002 * previousExposure / adaptedExposure)
        // NASA SVS: J2000, centre RA0h, increasing RA left, north pole at top.
        data[24] = -1; data[25] = 0.5; data[26] = -1; data[27] = 0.5
        values = data
    }

    private static func fade(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
