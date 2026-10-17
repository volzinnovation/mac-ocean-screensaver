import Foundation
import simd

@main enum CelestialSceneTests {
    static var count = 0
    static func check(_ value: Bool, _ message: String) {
        count += 1
        if !value { fatalError(message) }
    }
    static func main() {
        let location = GeographicCoordinate(latitude: 52.52, longitude: 13.405)
        for instant in ["2024-04-12T12:00:00Z", "2024-04-12T21:00:00Z", "2024-04-23T23:00:00Z", "2024-04-08T22:00:00Z"] {
            let date = ISO8601DateFormatter().date(from: instant)!
            let sky = CelestialFrame.calculate(date: date, coordinate: location)!
            let uniform = CelestialUniforms(frame: sky)
            check(uniform.values.count == 32 && uniform.values.count * MemoryLayout<Float>.stride == 128, "GPU celestial layout is exactly eight vec4s")
            check(uniform.values.allSatisfy(\.isFinite) && uniform.exposure.isFinite, "all celestial GPU data are finite")
            check(abs(Double(uniform.values[7]) - sky.moon.illuminatedFraction) < 1e-6, "GPU uses the calculated topocentric phase")
            check(uniform.values[24...27].elementsEqual([-1, 0.5, -1, 0.5]), "NASA atlas has the documented RA/declination orientation")
            let state = OceanFrameState()
            state.update(width: 1280, height: 800, deltaTime: 1 / 30, sun: sky.sun, headingDegrees: sky.viewAzimuthDegrees)
            let heading = atan2(Double(state.frameUniforms[28]), -Double(state.frameUniforms[30])) * 180 / .pi
            let difference = (heading - sky.viewAzimuthDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
            check(abs(difference) < 1e-4, "camera faces the selected astronomical body")
            let solarAzimuth = atan2(Double(state.frameUniforms[32]), -Double(state.frameUniforms[34])) * 180 / .pi
            let solarDifference = (solarAzimuth - sky.sun.azimuthDegrees + 540).truncatingRemainder(dividingBy: 360) - 180
            check(abs(solarDifference) < 1e-4, "switching camera to Moon never rotates the physical Sun")
            for equatorial in [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1)] {
                let local = sky.equatorialToLocal * equatorial
                let v = uniform.values
                let packed = SIMD3(simd_dot(SIMD3(v[8], v[9], v[10]), local),
                                   simd_dot(SIMD3(v[12], v[13], v[14]), local),
                                   simd_dot(SIMD3(v[16], v[17], v[18]), local))
                check(simd_length(packed - SIMD3(equatorial.x, equatorial.z, equatorial.y)) < 1e-5,
                      "local horizon rays reach correct atlas axes")
            }
            if sky.sun.elevationDegrees > 0 {
                check(!sky.isNight && uniform.values[20] == 0, "daytime faces Sun and hides stellar light")
            }
            if sky.sun.elevationDegrees < -18 {
                check(sky.isNight && uniform.values[20] == 1 && uniform.exposure > 50, "astronomical night faces Moon and adapts for stars")
            }
        }
        print("Celestial scene: \(count) assertions passed")
    }
}
