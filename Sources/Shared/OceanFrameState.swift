import Foundation
import simd

/// CPU half of the upstream ocean: fixed floating camera, uniform packing and
/// CDLOD selection. Float offsets intentionally match the original GPU structs.
final class OceanFrameState {
    static let grid = 32
    static let cascades = 6
    static let fftSize = 256
    static let foamResolution = 1024
    static let instanceCapacity = 8192
    static let cascadeLengths: [Float] = [1103, 211.3, 39.7, 7.43, 1.393, 0.2617]
    static let gridIndices: [UInt16] = {
        var result = [UInt16]()
        result.reserveCapacity(grid * grid * 6)
        for j in 0..<grid {
            for i in 0..<grid {
                let a = UInt16(i + j * (grid + 1)), b = a + 1
                let c = a + UInt16(grid + 1), d = c + 1
                result.append(contentsOf: [a, c, d, a, d, b])
            }
        }
        return result
    }()

    private(set) var frameUniforms = [Float](repeating: 0, count: 96)
    private(set) var simulationUniforms = [Float](repeating: 0, count: 56)
    private(set) var foamUniforms = [Float](repeating: 0, count: 36)
    /// Instance data: world x, world z, square size in metres, LOD level.
    private(set) var instances = [SIMD4<Float>]()
    private(set) var viewProjection = matrix_identity_float4x4
    private(set) var frameIndex = 0
    private(set) var time: Float = 0
    var cameraHeight: Float = 2.4
    var waterHeight: Float = 0

    private static let leaf: Double = 2
    private static let baseRange: Double = 16
    private static let lodCount = 17
    private static let maximumDistance: Double = 160000
    private static let verticalBound: Double = 4
    private static let horizontalBound: Double = 4
    private static let degreesToRadians = Double.pi / 180
    private static let windSpeed: Double = 7
    private static let windDirection = 118 * degreesToRadians
    private static let foamLevelSizes: [Float] = [128, 1024]
    // Keep the source decimal constants as doubles before writing Float uniforms.
    private static let lengths: [Double] = [1103, 211.3, 39.7, 7.43, 1.393, 0.2617]
    private let ranges = (0..<lodCount).map { baseRange * pow(2, Double($0)) }
    private var planes = [SIMD4<Double>](repeating: .zero, count: 4)
    private var firstFoamFrame = true
    private var accumulatedTime: Double = 0

    init() {
        instances.reserveCapacity(Self.instanceCapacity)
        writeSimulationStatic()
    }

    func update(width: Int, height: Int, deltaTime: Float, sun: SolarPosition, headingDegrees: Double? = nil) {
        let dt = deltaTime.isFinite ? min(0.1, max(0, deltaTime)) : 0
        if waterHeight.isFinite && cameraHeight < waterHeight + 0.9 {
            cameraHeight += (waterHeight + 0.9 - cameraHeight) * min(1, dt * 12)
        }
        accumulatedTime += Double(dt)
        if accumulatedTime > 600 { accumulatedTime -= 600 }
        time = Float(accumulatedTime)
        frameIndex += 1
        writeFrame(width: max(1, width), height: max(1, height), sun: sun, headingDegrees: headingDegrees)
        simulationUniforms[52] = time
        simulationUniforms[53] = dt
        writeFoam(deltaTime: dt)
        selectAll()
    }

    private func writeSimulationStatic() {
        for c in 0..<Self.cascades {
            let length = Self.lengths[c]
            simulationUniforms[c] = Float(length)
            simulationUniforms[8 + c] = Float(c == 0 ? .pi / length : 2 * .pi * 6 / length)
            simulationUniforms[16 + c] = Float(c < Self.cascades - 1
                ? 2 * .pi * 6 / Self.lengths[c + 1] : .pi * Double(Self.fftSize) / length * 0.98)
        }
        for c in 1..<Self.cascades { simulationUniforms[8 + c] = simulationUniforms[16 + c - 1] }
        simulationUniforms[40] = Float(Self.windSpeed)
        simulationUniforms[41] = Float(Self.windDirection)
        simulationUniforms[42] = 90000
        simulationUniforms[43] = 3.3
        simulationUniforms[44] = 1.8
        simulationUniforms[45] = Float(94 * Self.degreesToRadians)
        simulationUniforms[46] = Float(sqrt(9.81 * 2 * .pi / 120))
        simulationUniforms[47] = 48
        simulationUniforms[48] = 1.25
        simulationUniforms[49] = 0.0012
        simulationUniforms[50] = 600
        simulationUniforms[51] = 1
        simulationUniforms[54] = 2.2
        simulationUniforms[55] = 1
    }

    private func writeFrame(width: Int, height: Int, sun: SolarPosition, headingDegrees: Double?) {
        let aspect = Double(width) / Double(height)
        let tanY = tan(58 * Self.degreesToRadians * 0.5), tanX = tanY * aspect
        let heading = headingDegrees ?? sun.azimuthDegrees
        let yaw = (heading.isFinite ? heading : 0) * Self.degreesToRadians
        let pitch = -5.5 * Self.degreesToRadians
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let forward = SIMD3<Double>(cp * sy, sp, -cp * cy)
        let right = SIMD3<Double>(cy, 0, sy)
        let up = simd_cross(right, forward)

        // The original JS rounds both input matrices to Float32 before its
        // double-precision multiplication, then rounds the resulting matrix.
        let projection = simd_float4x4(columns: (
            SIMD4(Float(1 / tanX), 0, 0, 0), SIMD4(0, Float(1 / tanY), 0, 0),
            SIMD4(0, 0, 0, -1), SIMD4(0, 0, 0.05, 0)
        ))
        let view = simd_float4x4(columns: (
            SIMD4(Float(right.x), Float(up.x), Float(-forward.x), 0),
            SIMD4(Float(right.y), Float(up.y), Float(-forward.y), 0),
            SIMD4(Float(right.z), Float(up.z), Float(-forward.z), 0),
            SIMD4(0, 0, 0, 1)
        ))
        for c in 0..<4 {
            for r in 0..<4 {
                let value = Double(projection[0][r]) * Double(view[c][0])
                    + Double(projection[1][r]) * Double(view[c][1])
                    + Double(projection[2][r]) * Double(view[c][2])
                    + Double(projection[3][r]) * Double(view[c][3])
                viewProjection[c][r] = Float(value)
                frameUniforms[c * 4 + r] = Float(value)
            }
        }
        frameUniforms[16] = 0
        frameUniforms[17] = cameraHeight
        frameUniforms[18] = 0
        frameUniforms[19] = time
        for i in 0..<3 {
            frameUniforms[20 + i] = Float(right[i] * tanX)
            frameUniforms[24 + i] = Float(up[i] * tanY)
            frameUniforms[28 + i] = Float(forward[i])
        }
        let elevation = min(90, max(-90, sun.elevationDegrees.isFinite ? sun.elevationDegrees : 0)) * Self.degreesToRadians
        let solarAzimuth = sun.azimuthDegrees * Self.degreesToRadians
        frameUniforms[32] = Float(sin(solarAzimuth) * cos(elevation))
        frameUniforms[33] = Float(sin(elevation))
        frameUniforms[34] = Float(-cos(solarAzimuth) * cos(elevation))
        frameUniforms[35] = 14
        frameUniforms[36] = Float(width)
        frameUniforms[37] = Float(height)
        frameUniforms[38] = Float(1 / Double(width))
        frameUniforms[39] = Float(1 / Double(height))
        for c in 0..<Self.cascades {
            frameUniforms[40 + c] = Float(Self.lengths[c])
            frameUniforms[48 + c] = Float(1 / Self.lengths[c])
        }
        frameUniforms[56] = Float(cos(Self.windDirection))
        frameUniforms[57] = Float(sin(Self.windDirection))
        frameUniforms[58] = Float(Self.windSpeed)
        frameUniforms[64] = Float(Self.baseRange)
        frameUniforms[65] = Float(Self.grid)
        frameUniforms[66] = Self.foamLevelSizes[0]
        frameUniforms[67] = Self.foamLevelSizes[1]
        frameUniforms[68] = 1.35
        frameUniforms[69] = 0.10
        frameUniforms[70] = Float(frameIndex)
        frameUniforms[71] = 0
        frameUniforms[72] = 3
        frameUniforms[73] = Float(max(Double(cameraHeight), 10) * 0.001)
        frameUniforms[74] = 0.36
        frameUniforms[75] = 0.9
        frameUniforms[76] = Float(0.016 * 1.6)
        frameUniforms[77] = Float(0.080 * 1.6)
        frameUniforms[78] = Float(0.096 * 1.6)
        frameUniforms[79] = 0.0024
        frameUniforms[80] = 0.035
        frameUniforms[81] = 0.120
        frameUniforms[82] = 0.085
        frameUniforms[83] = 2.6
        frameUniforms[84] = Float(0.36 + 0.12)
        frameUniforms[85] = 2.5
        frameUniforms[86] = 1
        frameUniforms[87] = 1
        frameUniforms[88] = Float((5.802e-3 + 4.40e-3 * 3) * 1e-3)
        frameUniforms[89] = Float((13.558e-3 + 4.40e-3 * 3) * 1e-3)
        frameUniforms[90] = Float((33.1e-3 + 4.40e-3 * 3) * 1e-3)
        frameUniforms[91] = 1.1e-4
        frameUniforms[92] = 1.5
        frameUniforms[93] = 0.40
        frameUniforms[94] = 2.2
        frameUniforms[95] = time
    }

    private func writeFoam(deltaTime: Float) {
        for level in 0..<2 {
            // Fixed camera x/z are zero, so both clipmaps remain snapped to zero.
            foamUniforms[level * 4] = Float(bitPattern: 0)
            foamUniforms[level * 4 + 1] = Float(bitPattern: 0)
            let previous: Int32 = firstFoamFrame ? 100000 : 0
            foamUniforms[level * 4 + 2] = Float(bitPattern: UInt32(bitPattern: previous))
            foamUniforms[level * 4 + 3] = Float(bitPattern: UInt32(bitPattern: previous))
            foamUniforms[8 + level] = Self.foamLevelSizes[level] / Float(Self.foamResolution)
        }
        firstFoamFrame = false
        foamUniforms[10] = deltaTime
        foamUniforms[11] = 0.22
        foamUniforms[12] = Float(0.52 + 0.16)
        foamUniforms[13] = 2
        foamUniforms[14] = 1
        foamUniforms[15] = 0
        for c in 0..<Self.cascades {
            foamUniforms[16 + c] = Float(Self.lengths[c])
            foamUniforms[24 + c] = Float(1 / Self.lengths[c])
        }
        foamUniforms[32] = Float(cos(Self.windDirection) * 0.03 * Self.windSpeed)
        foamUniforms[33] = Float(sin(Self.windDirection) * 0.03 * Self.windSpeed)
    }

    private func sphereHit(x: Double, z: Double, size: Double, radius: Double) -> Bool {
        let dx = max(x, 0, -(x + size)), dz = max(z, 0, -(z + size))
        let dy = max(-Self.verticalBound - Double(cameraHeight), 0, Double(cameraHeight) - Self.verticalBound)
        return dx * dx + dy * dy + dz * dz <= radius * radius
    }

    private func inFrustum(x: Double, z: Double, size: Double) -> Bool {
        let minimum = SIMD3(x - Self.horizontalBound, -Self.verticalBound - Double(cameraHeight), z - Self.horizontalBound)
        let maximum = SIMD3(x + size + Self.horizontalBound, Self.verticalBound - Double(cameraHeight), z + size + Self.horizontalBound)
        for plane in planes {
            let p = SIMD3(plane.x > 0 ? maximum.x : minimum.x,
                          plane.y > 0 ? maximum.y : minimum.y,
                          plane.z > 0 ? maximum.z : minimum.z)
            if plane.x * p.x + plane.y * p.y + plane.z * p.z + plane.w < 0 { return false }
        }
        return true
    }

    private func addNode(x: Double, z: Double, size: Double, lod: Int) {
        guard instances.count < Self.instanceCapacity else { return }
        instances.append(SIMD4(Float(x), Float(z), Float(size), Float(lod)))
    }

    @discardableResult
    private func selectNode(x: Double, z: Double, size: Double, lod: Int) -> Bool {
        guard sphereHit(x: x, z: z, size: size, radius: ranges[lod]) else { return false }
        guard sphereHit(x: x, z: z, size: size, radius: Self.maximumDistance),
              inFrustum(x: x, z: z, size: size) else { return true }
        if lod == 0 || !sphereHit(x: x, z: z, size: size, radius: ranges[lod - 1]) {
            addNode(x: x, z: z, size: size, lod: lod)
            return true
        }
        let half = size * 0.5
        for i in 0..<4 {
            let nx = x + Double(i & 1) * half, nz = z + Double(i >> 1) * half
            if !selectNode(x: nx, z: nz, size: half, lod: lod - 1),
               sphereHit(x: nx, z: nz, size: half, radius: Self.maximumDistance),
               inFrustum(x: nx, z: nz, size: half) {
                addNode(x: nx, z: nz, size: half, lod: lod - 1)
            }
        }
        return true
    }

    private func selectAll() {
        instances.removeAll(keepingCapacity: true)
        for i in 0..<4 {
            let row = i >> 1, sign: Double = i & 1 == 0 ? 1 : -1
            planes[i] = SIMD4(
                Double(viewProjection[0][3]) + sign * Double(viewProjection[0][row]),
                Double(viewProjection[1][3]) + sign * Double(viewProjection[1][row]),
                Double(viewProjection[2][3]) + sign * Double(viewProjection[2][row]),
                Double(viewProjection[3][3]) + sign * Double(viewProjection[3][row])
            )
        }
        let top = Self.lodCount - 1
        let size = Self.leaf * pow(2, Double(top))
        let first = Int(floor(-Self.maximumDistance / size)), last = Int(floor(Self.maximumDistance / size))
        for zi in first...last {
            for xi in first...last { selectNode(x: Double(xi) * size, z: Double(zi) * size, size: size, lod: top) }
        }
    }
}
