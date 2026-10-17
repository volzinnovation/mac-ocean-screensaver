import AppKit
import Metal
import MetalKit
import QuartzCore

/// Direct Metal execution of the original ocean's WGSL, translated at development time.
/// This class never creates a WebKit process or a remote web-content layer.
final class OceanMetalRenderer {
    struct RenderError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    let device: MTLDevice
    let state = OceanFrameState()
    private let queue: MTLCommandQueue
    private let inFlight = DispatchSemaphore(value: 3)
    private var ring = 0
    private var computes: [String: MTLComputePipelineState] = [:]
    private var renders: [String: MTLRenderPipelineState] = [:]
    private var libraries: [String: MTLLibrary] = [:]
    private var buffers: [String: MTLBuffer] = [:]
    private var textures: [String: MTLTexture] = [:]
    private var views: [String: [MTLTexture]] = [:]
    private var instances: [MTLBuffer] = []
    private var probes: [MTLBuffer] = []
    private let samplerClamp: MTLSamplerState
    private let samplerRepeat: MTLSamplerState
    private let samplerSimulation: MTLSamplerState
    private let samplerLinear: MTLSamplerState
    private let samplerStars: MTLSamplerState
    private let depthOcean: MTLDepthStencilState
    private let depthSky: MTLDepthStencilState
    private var first = true
    private var environmentRefreshFrames = 2
    private var previousSolarAngles: SIMD2<Double>?
    private var foamCurrent = 0
    private var size = SIMD2<Int>(0, 0)
    private var bloomLevels = 1
    private var celestialValues = [Float](repeating: 0, count: 32)
    private var exposure: Float = 1.35
    private(set) var output: MTLTexture?
    private(set) var completedFrames = 0

    init(bundle: Bundle) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw RenderError(message: "Metal is not available on this Mac.")
        }
        self.device = device
        self.queue = queue
        func sampler(repeating: Bool, mipmapped: Bool = true, anisotropy: Int = 1) -> MTLSamplerState {
            let descriptor = MTLSamplerDescriptor()
            descriptor.minFilter = .linear; descriptor.magFilter = .linear
            descriptor.mipFilter = mipmapped ? .linear : .notMipmapped
            descriptor.sAddressMode = repeating ? .repeat : .clampToEdge
            descriptor.tAddressMode = repeating ? .repeat : .clampToEdge
            descriptor.rAddressMode = .clampToEdge
            descriptor.maxAnisotropy = anisotropy
            return device.makeSamplerState(descriptor: descriptor)!
        }
        samplerClamp = sampler(repeating: false)
        samplerRepeat = sampler(repeating: true, anisotropy: 16)
        samplerSimulation = sampler(repeating: true)
        samplerLinear = sampler(repeating: false, mipmapped: false)
        let starSampler = MTLSamplerDescriptor()
        starSampler.minFilter = .linear; starSampler.magFilter = .linear; starSampler.mipFilter = .linear
        starSampler.sAddressMode = .repeat; starSampler.tAddressMode = .clampToEdge
        samplerStars = device.makeSamplerState(descriptor: starSampler)!
        let oceanDepth = MTLDepthStencilDescriptor()
        oceanDepth.depthCompareFunction = .greater; oceanDepth.isDepthWriteEnabled = true
        depthOcean = device.makeDepthStencilState(descriptor: oceanDepth)!
        let skyDepth = MTLDepthStencilDescriptor()
        skyDepth.depthCompareFunction = .equal; skyDepth.isDepthWriteEnabled = false
        depthSky = device.makeDepthStencilState(descriptor: skyDepth)!
        let computeNames = ["SIM_INIT", "SIM_EVOLVE", "FFT_ROWS", "FFT_COLS", "SIM_MIPS", "FOAM_TEX", "RGBA8_MIPS", "FOAM_UPDATE", "ARRAY16_MIPS", "TRANS_LUT", "MS_LUT", "SKYVIEW_LUT", "ENV_CUBE", "CUBE_MIPS", "SUN_VIS", "HEIGHT_PROBE"]
        for name in computeNames + ["OCEAN", "SKY_BG", "BLOOM_DOWN", "BLOOM_UP", "COMPOSITE"] {
            guard let url = bundle.url(forResource: name, withExtension: "metallib", subdirectory: "Metal") else {
                throw RenderError(message: "Missing native shader \(name). Rebuild Ocean.saver.")
            }
            libraries[name] = try device.makeLibrary(URL: url)
        }
        for name in computeNames {
            let library = libraries[name]!
            guard let function = library.makeFunction(name: "main") ?? library.makeFunction(name: "main_") else {
                throw RenderError(message: "No compute entry point in \(name): \(library.functionNames)")
            }
            computes[name] = try device.makeComputePipelineState(function: function)
        }
        for name in ["OCEAN", "SKY_BG", "BLOOM_DOWN", "BLOOM_UP", "COMPOSITE"] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = name
            descriptor.vertexFunction = libraries[name]!.makeFunction(name: "vs")
            descriptor.fragmentFunction = libraries[name]!.makeFunction(name: "fs")
            descriptor.colorAttachments[0].pixelFormat = name == "COMPOSITE" ? .bgra8Unorm : .rgba16Float
            if name == "OCEAN" || name == "SKY_BG" {
                descriptor.rasterSampleCount = 4
                descriptor.depthAttachmentPixelFormat = .depth32Float
            }
            if name == "OCEAN" {
                let vertex = MTLVertexDescriptor()
                vertex.attributes[0].format = .float4
                vertex.attributes[0].offset = 0
                vertex.attributes[0].bufferIndex = 30
                vertex.layouts[30].stride = 16
                vertex.layouts[30].stepFunction = .perInstance
                descriptor.vertexDescriptor = vertex
            }
            if name == "BLOOM_UP" {
                let attachment = descriptor.colorAttachments[0]!
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one; attachment.destinationRGBBlendFactor = .one
                attachment.sourceAlphaBlendFactor = .one; attachment.destinationAlphaBlendFactor = .one
            }
            renders[name] = try device.makeRenderPipelineState(descriptor: descriptor)
        }
        let spectrumBytes = 256 * 256 * 6 * 16
        for name in ["h0", "specA", "specB", "tmpA", "tmpB"] {
            buffers[name] = try makeBuffer(length: spectrumBytes, label: name, options: .storageModePrivate)
        }
        buffers["sunVisibility"] = try makeBuffer(length: 16, label: "sun visibility", options: .storageModePrivate)
        let indices = OceanFrameState.gridIndices
        buffers["indices"] = indices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }
        for index in 0..<3 {
            instances.append(try makeBuffer(length: 8192 * 16, label: "instances \(index)", options: .storageModeShared))
            probes.append(try makeBuffer(length: 16, label: "height probe \(index)", options: .storageModeShared))
        }
        for name in ["displacement", "derivatives", "moments"] {
            textures[name] = try makeTexture(width: 256, height: 256, slices: 6, mips: 9, label: name)
            views[name] = try mipViews(textures[name]!)
        }
        textures["foamDetail"] = try makeTexture(width: 512, height: 512, mips: 10, format: .rgba8Unorm, label: "foam detail")
        views["foamDetail"] = try mipViews(textures["foamDetail"]!)
        for index in 0..<2 {
            let name = "foam\(index)"
            textures[name] = try makeTexture(width: 1024, height: 1024, slices: 2, mips: 11, label: name)
            views[name] = try mipViews(textures[name]!)
        }
        textures["transmittance"] = try makeTexture(width: 256, height: 64, label: "transmittance")
        textures["multiscatter"] = try makeTexture(width: 32, height: 32, label: "multiscatter")
        textures["sky"] = try makeTexture(width: 256, height: 144, label: "sky view")
        textures["environment"] = try makeTexture(width: 256, height: 256, slices: 6, mips: 9, cube: true, label: "environment cube")
        views["environment"] = try mipViews(textures["environment"]!, arrayView: true)
        guard let atlasURL = bundle.url(forResource: "starmap_2020_4k_srgb", withExtension: "png", subdirectory: "Sky") else {
            throw RenderError(message: "The measured star atlas is missing. Rebuild Ocean.saver.")
        }
        textures["stars"] = try MTKTextureLoader(device: device).newTexture(URL: atlasURL, options: [
            .SRGB: true, .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: true, .textureUsage: MTLTextureUsage.shaderRead.rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
    }

    private func makeBuffer(length: Int, label: String, options: MTLResourceOptions) throws -> MTLBuffer {
        guard let buffer = device.makeBuffer(length: length, options: options) else { throw RenderError(message: "Could not allocate \(label).") }
        buffer.label = label
        return buffer
    }

    private func makeTexture(width: Int, height: Int, slices: Int = 1, mips: Int = 1, format: MTLPixelFormat = .rgba16Float,
                             samples: Int = 1, cube: Bool = false, render: Bool = false, label: String) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.width = width; descriptor.height = height
        descriptor.textureType = samples > 1 ? .type2DMultisample : cube ? .typeCube : slices > 1 ? .type2DArray : .type2D
        descriptor.arrayLength = cube ? 1 : slices
        descriptor.pixelFormat = format; descriptor.mipmapLevelCount = mips; descriptor.sampleCount = samples
        descriptor.storageMode = .private
        descriptor.usage = render ? [.renderTarget, .shaderRead, .pixelFormatView] : [.shaderRead, .shaderWrite, .pixelFormatView]
        guard let texture = device.makeTexture(descriptor: descriptor) else { throw RenderError(message: "Could not allocate \(label).") }
        texture.label = label
        return texture
    }

    private func mipViews(_ texture: MTLTexture, arrayView: Bool = false) throws -> [MTLTexture] {
        let count = texture.textureType == .typeCube ? 6 : texture.arrayLength
        return try (0..<texture.mipmapLevelCount).map { level in
            guard let view = texture.makeTextureView(pixelFormat: texture.pixelFormat,
                                                     textureType: arrayView ? .type2DArray : texture.textureType,
                                                     levels: level..<(level + 1), slices: 0..<count) else {
                throw RenderError(message: "Could not create mip view for \(texture.label ?? "texture").")
            }
            return view
        }
    }

    private func resize(width: Int, height: Int) throws {
        guard size != SIMD2(width, height) else { return }
        size = SIMD2(width, height)
        textures["colorMS"] = try makeTexture(width: width, height: height, samples: 4, render: true, label: "MSAA scene")
        textures["depthMS"] = try makeTexture(width: width, height: height, format: .depth32Float, samples: 4, render: true, label: "MSAA depth")
        textures["hdr"] = try makeTexture(width: width, height: height, render: true, label: "HDR scene")
        let bw = max(1, width / 2), bh = max(1, height / 2)
        bloomLevels = min(8, Int(floor(log2(Double(max(bw, bh))))) + 1)
        textures["bloom"] = try makeTexture(width: bw, height: bh, mips: bloomLevels, render: true, label: "bloom")
        views["bloom"] = try mipViews(textures["bloom"]!)
        output = try makeTexture(width: width, height: height, format: .bgra8Unorm, render: true, label: "Ocean output")
    }

    private func bytes(_ encoder: MTLComputeCommandEncoder, _ values: [Float], at index: Int) {
        values.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: index) }
    }
    private func frameBytes(_ encoder: MTLRenderCommandEncoder, _ values: [Float], at index: Int, vertex: Bool = false) {
        values.withUnsafeBytes {
            encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: index)
            if vertex { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: index) }
        }
    }
    private func compute(_ encoder: MTLComputeCommandEncoder, _ name: String, groups: MTLSize, threads: MTLSize = MTLSize(width: 8, height: 8, depth: 1), bind: () -> Void) {
        encoder.setComputePipelineState(computes[name]!)
        bind()
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threads)
        encoder.memoryBarrier(scope: [.buffers, .textures])
    }
    private func groups(_ width: Int, _ height: Int = 1, _ depth: Int = 1) -> MTLSize { MTLSize(width: width, height: height, depth: depth) }

    func render(width: Int, height: Int, deltaTime: Float, celestial: CelestialFrame, drawable: CAMetalDrawable?, completion: @escaping (Error?) -> Void) throws {
        guard inFlight.wait(timeout: .now()) == .success else { return }
        var submitted = false
        defer { if !submitted { inFlight.signal() } }
        try resize(width: width, height: height)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw RenderError(message: "Could not create a Metal command buffer.") }
        command.label = "Ocean frame"
        let currentRing = ring
        ring = (ring + 1) % 3
        let sun = celestial.sun
        let celestialUniforms = CelestialUniforms(frame: celestial)
        celestialValues = celestialUniforms.values
        exposure = celestialUniforms.exposure
        state.update(width: width, height: height, deltaTime: deltaTime, sun: sun, headingDegrees: celestial.viewAzimuthDegrees)
        let angles = SIMD2(sun.azimuthDegrees, sun.elevationDegrees)
        if previousSolarAngles != angles { environmentRefreshFrames = 2; previousSolarAngles = angles }
        state.instances.withUnsafeBytes { data in
            if data.count > 0 { instances[currentRing].contents().copyMemory(from: data.baseAddress!, byteCount: data.count) }
        }
        if first {
            compute(encoder, "FOAM_TEX", groups: groups(64, 64)) { encoder.setTexture(views["foamDetail"]![0], index: 0) }
            for level in 1..<10 {
                let n = max(1, 512 >> level)
                compute(encoder, "RGBA8_MIPS", groups: groups((n + 7) / 8, (n + 7) / 8)) {
                    encoder.setTexture(views["foamDetail"]![level - 1], index: 0); encoder.setTexture(views["foamDetail"]![level], index: 1)
                }
            }
            compute(encoder, "SIM_INIT", groups: groups(16, 16, 6), threads: groups(16, 16)) {
                bytes(encoder, state.simulationUniforms, at: 0); encoder.setBuffer(buffers["h0"], offset: 0, index: 1)
            }
            compute(encoder, "TRANS_LUT", groups: groups(32, 8)) {
                bytes(encoder, [3, 0, 0, 0], at: 0); encoder.setTexture(textures["transmittance"], index: 1)
            }
            compute(encoder, "MS_LUT", groups: groups(4, 4)) {
                bytes(encoder, [3, 0, 0, 0], at: 0); encoder.setTexture(textures["transmittance"], index: 1)
                encoder.setSamplerState(samplerClamp, index: 2); encoder.setTexture(textures["multiscatter"], index: 3)
            }
            first = false
        }
        compute(encoder, "SIM_EVOLVE", groups: groups(16, 16, 6), threads: groups(16, 16)) {
            bytes(encoder, state.simulationUniforms, at: 0)
            for (index, name) in ["h0", "specA", "specB"].enumerated() { encoder.setBuffer(buffers[name], offset: 0, index: index + 1) }
        }
        compute(encoder, "FFT_ROWS", groups: groups(256, 1, 6), threads: groups(128)) {
            for (index, name) in ["specA", "specB", "tmpA", "tmpB"].enumerated() { encoder.setBuffer(buffers[name], offset: 0, index: index) }
        }
        compute(encoder, "FFT_COLS", groups: groups(256, 1, 6), threads: groups(128)) {
            encoder.setBuffer(buffers["tmpA"], offset: 0, index: 0); encoder.setBuffer(buffers["tmpB"], offset: 0, index: 1)
            for (index, name) in ["displacement", "derivatives", "moments"].enumerated() { encoder.setTexture(views[name]![0], index: index + 2) }
        }
        for level in 1..<9 {
            let n = max(1, 256 >> level)
            compute(encoder, "SIM_MIPS", groups: groups((n + 7) / 8, (n + 7) / 8, 6)) {
                for (index, name) in ["displacement", "derivatives", "moments"].enumerated() {
                    encoder.setTexture(views[name]![level - 1], index: index); encoder.setTexture(views[name]![level], index: index + 3)
                }
            }
        }
        foamCurrent = 1 - foamCurrent
        let foam = "foam\(foamCurrent)", previousFoam = "foam\(1 - foamCurrent)"
        compute(encoder, "FOAM_UPDATE", groups: groups(128, 128, 2)) {
            bytes(encoder, state.foamUniforms, at: 0)
            encoder.setTexture(views[previousFoam]![0], index: 1); encoder.setTexture(views[foam]![0], index: 2)
            encoder.setTexture(textures["displacement"], index: 3); encoder.setTexture(textures["derivatives"], index: 4)
            encoder.setSamplerState(samplerSimulation, index: 5); encoder.setSamplerState(samplerSimulation, index: 6)
        }
        for level in 1..<11 {
            let n = max(1, 1024 >> level)
            compute(encoder, "ARRAY16_MIPS", groups: groups((n + 7) / 8, (n + 7) / 8, 2)) {
                encoder.setTexture(views[foam]![level - 1], index: 0); encoder.setTexture(views[foam]![level], index: 1)
            }
        }
        compute(encoder, "HEIGHT_PROBE", groups: groups(1), threads: groups(1)) {
            bytes(encoder, state.frameUniforms, at: 0); encoder.setTexture(textures["displacement"], index: 1)
            encoder.setSamplerState(samplerSimulation, index: 2); encoder.setBuffer(probes[currentRing], offset: 0, index: 3)
        }
        compute(encoder, "SKYVIEW_LUT", groups: groups(32, 18)) {
            bytes(encoder, state.frameUniforms, at: 0); encoder.setTexture(textures["transmittance"], index: 1)
            encoder.setTexture(textures["multiscatter"], index: 2); encoder.setSamplerState(samplerClamp, index: 3)
            encoder.setTexture(textures["sky"], index: 4)
        }
        compute(encoder, "SUN_VIS", groups: groups(1), threads: groups(8)) {
            bytes(encoder, state.frameUniforms, at: 0); encoder.setTexture(textures["transmittance"], index: 1)
            encoder.setTexture(textures["sky"], index: 2); encoder.setSamplerState(samplerClamp, index: 3)
            encoder.setBuffer(buffers["sunVisibility"], offset: 0, index: 4)
        }
        compute(encoder, "ENV_CUBE", groups: groups(32, 32, environmentRefreshFrames > 0 ? 6 : 1)) {
            bytes(encoder, state.frameUniforms, at: 0); encoder.setTexture(textures["transmittance"], index: 1)
            encoder.setTexture(textures["sky"], index: 2); encoder.setSamplerState(samplerClamp, index: 3)
            encoder.setTexture(views["environment"]![0], index: 4)
            bytes(encoder, celestialValues, at: 12)
            encoder.setTexture(textures["stars"], index: 13); encoder.setSamplerState(samplerStars, index: 14)
        }
        environmentRefreshFrames = max(0, environmentRefreshFrames - 1)
        for level in 1..<9 {
            let n = max(1, 256 >> level)
            compute(encoder, "CUBE_MIPS", groups: groups((n + 7) / 8, (n + 7) / 8, 6)) {
                encoder.setTexture(views["environment"]![level - 1], index: 0); encoder.setTexture(views["environment"]![level], index: 1)
            }
        }
        encoder.endEncoding()
        try encodeScene(command, ring: currentRing, foam: foam)
        try encodePost(command, drawable: drawable)
        let probe = probes[currentRing]
        command.addCompletedHandler { [weak self, inFlight] completed in
            let height = probe.contents().load(as: Float.self)
            DispatchQueue.main.async { [weak self] in
                self?.state.waterHeight = height.isFinite ? height : 0
                if completed.status == .completed { self?.completedFrames += 1 }
                completion(completed.error)
            }
            inFlight.signal()
        }
        command.commit()
        submitted = true
    }

    private func encodeScene(_ command: MTLCommandBuffer, ring: Int, foam: String) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = textures["colorMS"]
        pass.colorAttachments[0].resolveTexture = textures["hdr"]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        pass.depthAttachment.texture = textures["depthMS"]
        pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 0
        guard let render = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError(message: "Could not encode the ocean scene.") }
        render.label = "Ocean and atmosphere"
        render.setCullMode(.none)
        frameBytes(render, state.frameUniforms, at: 0, vertex: true)
        frameBytes(render, celestialValues, at: 12)
        render.setFragmentTexture(textures["transmittance"], index: 1)
        render.setFragmentTexture(textures["sky"], index: 2)
        render.setFragmentSamplerState(samplerClamp, index: 3)
        if !state.instances.isEmpty {
            render.setRenderPipelineState(renders["OCEAN"]!)
            render.setDepthStencilState(depthOcean)
            render.setVertexBuffer(instances[ring], offset: 0, index: 30)
            for (index, name) in ["displacement", "derivatives", "moments"].enumerated() {
                render.setVertexTexture(textures[name], index: index + 4)
                render.setFragmentTexture(textures[name], index: index + 4)
            }
            render.setVertexSamplerState(samplerRepeat, index: 9)
            render.setFragmentSamplerState(samplerRepeat, index: 9)
            render.setFragmentTexture(textures["foamDetail"], index: 7)
            render.setFragmentTexture(textures["environment"], index: 8)
            render.setFragmentTexture(textures[foam], index: 10)
            render.setFragmentBuffer(buffers["sunVisibility"], offset: 0, index: 11)
            render.drawIndexedPrimitives(type: .triangle, indexCount: OceanFrameState.gridIndices.count,
                                         indexType: .uint16, indexBuffer: buffers["indices"]!, indexBufferOffset: 0,
                                         instanceCount: state.instances.count)
        }
        render.setRenderPipelineState(renders["SKY_BG"]!)
        render.setFragmentTexture(textures["stars"], index: 13)
        render.setFragmentSamplerState(samplerStars, index: 14)
        render.setDepthStencilState(depthSky)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
    }

    private func encodePost(_ command: MTLCommandBuffer, drawable: CAMetalDrawable?) throws {
        let bloom = views["bloom"]!
        func renderPass(name: String, target: MTLTexture, source: MTLTexture, values: [Float], load: MTLLoadAction = .clear) throws {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = load; pass.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError(message: "Could not encode \(name).") }
            encoder.label = name
            encoder.setRenderPipelineState(renders[name]!)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentSamplerState(samplerLinear, index: 1)
            frameBytes(encoder, values, at: 2)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        for level in 0..<bloomLevels {
            let source = level == 0 ? textures["hdr"]! : bloom[level - 1]
            try renderPass(name: "BLOOM_DOWN", target: bloom[level], source: source,
                           values: [1 / Float(source.width), 1 / Float(source.height), level == 0 ? 1 : 0, 0])
        }
        if bloomLevels > 1 {
            for level in stride(from: bloomLevels - 1, through: 1, by: -1) {
                let source = bloom[level]
                try renderPass(name: "BLOOM_UP", target: bloom[level - 1], source: source,
                               values: [1 / Float(source.width), 1 / Float(source.height), 1, 1], load: .load)
            }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw RenderError(message: "Could not encode tone mapping.") }
        encoder.label = "AgX tone mapping"
        encoder.setRenderPipelineState(renders["COMPOSITE"]!)
        encoder.setFragmentTexture(textures["hdr"], index: 0)
        encoder.setFragmentTexture(bloom[0], index: 1)
        encoder.setFragmentSamplerState(samplerLinear, index: 2)
        frameBytes(encoder, [exposure, 0.10, Float(state.frameIndex % 64), 0.10, 1.05, 1.06, -0.19, Float(bloomLevels)], at: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable, let output, let blit = command.makeBlitCommandEncoder() {
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                      sourceSize: .init(width: size.x, height: size.y, depth: 1), to: drawable.texture,
                      destinationSlice: 0, destinationLevel: 0, destinationOrigin: .init(x: 0, y: 0, z: 0))
            blit.endEncoding()
            command.present(drawable)
        }
    }

    func snapshot(to url: URL) throws {
        guard let output, let command = queue.makeCommandBuffer(), let encoder = command.makeBlitCommandEncoder() else {
            throw RenderError(message: "The native ocean has not rendered a frame yet.")
        }
        let rowBytes = ((output.width * 4 + 255) / 256) * 256
        let buffer = try makeBuffer(length: rowBytes * output.height, label: "snapshot", options: .storageModeShared)
        encoder.copy(from: output, sourceSlice: 0, sourceLevel: 0, sourceOrigin: .init(x: 0, y: 0, z: 0),
                     sourceSize: .init(width: output.width, height: output.height, depth: 1),
                     to: buffer, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * output.height)
        encoder.endEncoding()
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        let data = Data(bytes: buffer.contents(), count: buffer.length)
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: output.width, height: output.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw RenderError(message: "Could not encode the native ocean snapshot.")
        }
        try png.write(to: url)
    }
}
