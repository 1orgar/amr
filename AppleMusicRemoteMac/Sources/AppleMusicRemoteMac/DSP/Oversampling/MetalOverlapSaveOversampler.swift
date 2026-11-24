import Accelerate
import Darwin
import Foundation
import Metal
import simd

/// Режим `Sinc-M (Ultra-Long Sinc)` на GPU Apple Silicon (`Metal` + `StorageMode.shared` + `df64` Double-Float).
///
/// Выполняет массивную полифазную свёртку КИХ-фильтра Кайзера Stage 1 (`16 384 .. 65 536` тапов, `> 160 dB`
/// подавление боковых лепестков) в парной арифметике Деккера–Кнута `df64 = SIMD2<Float>(hi, lo)` на GPU
/// без копирования между CPU и GPU (Unified Memory Zero-Copy + `mlock`)
/// и с бесшовной синхронизацией линии задержки при резервировании на `AccelerateAMXOversampler`.
public final class MetalOverlapSaveOversampler: OversamplerBackend, @unchecked Sendable {
    public let backendKind: OversamplerBackendKind = .metalOverlapSave
    public var phaseMode: OversamplerPhaseMode {
        didSet {
            cpuFallback.phaseMode = phaseMode
            if phaseMode != oldValue {
                uploadPolyphaseWeightsToGPU()
            }
        }
    }

    public let tapsPerPhase: Int
    private let cpuFallback: AccelerateAMXOversampler

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLComputePipelineState?

    // Unified Memory (.storageModeShared) буферы, зафиксированные в физической RAM через mlock()
    private var weightsBufferR2: MTLBuffer?
    private var weightsBufferR4: MTLBuffer?
    private var weightsBufferR8: MTLBuffer?
    private var inputBufferL: MTLBuffer?
    private var inputBufferR: MTLBuffer?
    private var outputBufferL: MTLBuffer?
    private var outputBufferR: MTLBuffer?

    private let histLPtr: UnsafeMutablePointer<SIMD2<Float>>
    private let histRPtr: UnsafeMutablePointer<SIMD2<Float>>
    private let histCount: Int
    private let dxdScratch: AlignedPlanarDoubleBuffer
    private let maxInputFrames: Int

    private enum Stage1Owner {
        case none
        case gpu
        case cpu
    }
    private var lastStage1Owner: Stage1Owner = .none
    private var lastInputRateHz: Int = 0

    private struct PolyphaseDispatchParams {
        var inputFrames: UInt32
        var factor: UInt32
        var tapsPerPhase: UInt32
    }

    public init(
        phaseMode: OversamplerPhaseMode = .linearPhase,
        tapsPerPhase: Int = 1024,
        maxInputFrames: Int = 4096
    ) {
        let clampedTaps = max(128, min(tapsPerPhase, 4096))
        let hCount = clampedTaps - 1
        self.phaseMode = phaseMode
        self.tapsPerPhase = clampedTaps
        self.maxInputFrames = maxInputFrames
        self.histCount = hCount

        let hBytes = max(64, ((hCount * MemoryLayout<SIMD2<Float>>.stride) + 63) & ~63)
        var rawHL: UnsafeMutableRawPointer?
        var rawHR: UnsafeMutableRawPointer?
        let rcHL = posix_memalign(&rawHL, 64, hBytes)
        let rcHR = posix_memalign(&rawHR, 64, hBytes)
        guard rcHL == 0, let validHL = rawHL, rcHR == 0, let validHR = rawHR else {
            if let validHL = rawHL { free(validHL) }
            if let validHR = rawHR { free(validHR) }
            fatalError("posix_memalign(64, \(hBytes)) failed in MetalOverlapSaveOversampler (rcL=\(rcHL), rcR=\(rcHR))")
        }

        self.histLPtr = validHL.bindMemory(to: SIMD2<Float>.self, capacity: hCount)
        self.histRPtr = validHR.bindMemory(to: SIMD2<Float>.self, capacity: hCount)
        self.histLPtr.initialize(repeating: .zero, count: hCount)
        self.histRPtr.initialize(repeating: .zero, count: hCount)
        _ = mlock(validHL, hBytes)
        _ = mlock(validHR, hBytes)

        self.dxdScratch = AlignedPlanarDoubleBuffer(capacityFrames: maxInputFrames * 8 + 64)
        self.cpuFallback = AccelerateAMXOversampler(
            phaseMode: phaseMode,
            tapsPerPhase: min(clampedTaps, 512),
            maxInputFrames: maxInputFrames
        )

        let mtlDevice = MTLCreateSystemDefaultDevice()
        self.device = mtlDevice
        self.commandQueue = mtlDevice?.makeCommandQueue()

        let compileOptions = MTLCompileOptions()
        if #available(macOS 15.0, *) {
            compileOptions.mathMode = .safe
        }

        if let mtlDevice,
           let library = try? mtlDevice.makeLibrary(source: Self.embeddedMetalSource, options: compileOptions),
           let fn = library.makeFunction(name: "polyphase_fir_df64_stereo"),
           let pso = try? mtlDevice.makeComputePipelineState(function: fn) {
            self.pipelineState = pso
            allocateAndLockSharedBuffers(device: mtlDevice)
            uploadPolyphaseWeightsToGPU()
        } else {
            self.pipelineState = nil
        }
    }

    deinit {
        let hBytes = max(64, ((histCount * MemoryLayout<SIMD2<Float>>.stride) + 63) & ~63)
        _ = munlock(histLPtr, hBytes)
        _ = munlock(histRPtr, hBytes)
        free(histLPtr)
        free(histRPtr)

        unlockBuffer(weightsBufferR2)
        unlockBuffer(weightsBufferR4)
        unlockBuffer(weightsBufferR8)
        unlockBuffer(inputBufferL)
        unlockBuffer(inputBufferR)
        unlockBuffer(outputBufferL)
        unlockBuffer(outputBufferR)
    }

    public func reset() {
        memset(histLPtr, 0, histCount * MemoryLayout<SIMD2<Float>>.stride)
        memset(histRPtr, 0, histCount * MemoryLayout<SIMD2<Float>>.stride)
        lastStage1Owner = .none
        lastInputRateHz = 0
        cpuFallback.reset()
    }

    // MARK: - Double <-> Double-Float (df64) Conversion

    @inlinable
    public static func doubleToDF64(_ x: Double) -> SIMD2<Float> {
        let hi = Float(x)
        let lo = Float(x - Double(hi))
        return SIMD2<Float>(hi, lo)
    }

    @inlinable
    public static func df64ToDouble(_ v: SIMD2<Float>) -> Double {
        return Double(v.x) + Double(v.y)
    }

    // MARK: - Unified Memory Allocation & mlock()

    private func makeLockedSharedBuffer(device: MTLDevice, byteLength: Int) -> MTLBuffer? {
        let alignedLen = max(4096, (byteLength + 4095) & ~4095)
        guard let buf = device.makeBuffer(length: alignedLen, options: .storageModeShared) else {
            return nil
        }
        _ = mlock(buf.contents(), buf.length)
        return buf
    }

    private func unlockBuffer(_ buffer: MTLBuffer?) {
        guard let buffer else { return }
        _ = munlock(buffer.contents(), buffer.length)
    }

    private func allocateAndLockSharedBuffers(device: MTLDevice) {
        let df64Stride = MemoryLayout<SIMD2<Float>>.stride
        let inTotalSamples = maxInputFrames + tapsPerPhase + 16
        let outTotalSamples = maxInputFrames * 8 + 64

        inputBufferL = makeLockedSharedBuffer(device: device, byteLength: inTotalSamples * df64Stride)
        inputBufferR = makeLockedSharedBuffer(device: device, byteLength: inTotalSamples * df64Stride)
        outputBufferL = makeLockedSharedBuffer(device: device, byteLength: outTotalSamples * df64Stride)
        outputBufferR = makeLockedSharedBuffer(device: device, byteLength: outTotalSamples * df64Stride)

        weightsBufferR2 = makeLockedSharedBuffer(device: device, byteLength: 2 * tapsPerPhase * df64Stride)
        weightsBufferR4 = makeLockedSharedBuffer(device: device, byteLength: 4 * tapsPerPhase * df64Stride)
        weightsBufferR8 = makeLockedSharedBuffer(device: device, byteLength: 8 * tapsPerPhase * df64Stride)
    }

    private func uploadPolyphaseWeightsToGPU() {
        uploadBank(factor: 2, targetBuffer: weightsBufferR2)
        uploadBank(factor: 4, targetBuffer: weightsBufferR4)
        uploadBank(factor: 8, targetBuffer: weightsBufferR8)
    }

    private func uploadBank(factor: Int, targetBuffer: MTLBuffer?) {
        guard let targetBuffer else { return }
        let bank = AccelerateAMXOversampler.synthesizePolyphaseBank(
            factor: factor,
            tapsPerPhase: tapsPerPhase,
            phaseMode: phaseMode,
            beta: 16.0
        )
        let dst = targetBuffer.contents().bindMemory(to: SIMD2<Float>.self, capacity: factor * tapsPerPhase)
        var idx = 0
        for p in 0..<factor {
            for k in 0..<tapsPerPhase {
                dst[idx] = Self.doubleToDF64(bank[p][k])
                idx &+= 1
            }
        }
    }

    private func runCPUFallbackWithSyncedHistory(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        inputRateHz: Int,
        targetRateHz: Int,
        outputBuffer: AlignedPlanarDoubleBuffer
    ) -> Int {
        if lastStage1Owner == .gpu {
            cpuFallback.importStage1HistoryFromDF64(histL: histLPtr, histR: histRPtr, count: histCount)
        }
        lastStage1Owner = .cpu
        return cpuFallback.oversampleStereoBlock(
            inputL: inputL,
            inputR: inputR,
            inputFrames: inputFrames,
            inputRateHz: inputRateHz,
            targetRateHz: targetRateHz,
            outputBuffer: outputBuffer
        )
    }

    // MARK: - Oversample Execution

    public func oversampleStereoBlock(
        inputL: UnsafePointer<Double>,
        inputR: UnsafePointer<Double>,
        inputFrames: Int,
        inputRateHz: Int,
        targetRateHz: Int,
        outputBuffer: AlignedPlanarDoubleBuffer
    ) -> Int {
        guard inputFrames > 0, inputRateHz > 0 else { return 0 }

        if lastInputRateHz != 0 && lastInputRateHz != inputRateHz {
            reset()
        }
        lastInputRateHz = inputRateHz

        guard inputFrames <= maxInputFrames else {
            return runCPUFallbackWithSyncedHistory(
                inputL: inputL,
                inputR: inputR,
                inputFrames: inputFrames,
                inputRateHz: inputRateHz,
                targetRateHz: targetRateHz,
                outputBuffer: outputBuffer
            )
        }

        let isTarget44k1Grid = (targetRateHz % 44_100 == 0)
        let dxdRateHz = isTarget44k1Grid ? 352_800 : 384_000
        let isInput44k1Grid = (inputRateHz % 44_100 == 0)
        let factorStage1 = dxdRateHz / max(1, inputRateHz)

        // Если вход уже DXD (OSR < 32), требуется ASRC между сетками или Metal недоступен — используем AMX конвейер
        guard inputRateHz < 352_800,
              isInput44k1Grid == isTarget44k1Grid,
              (factorStage1 == 2 || factorStage1 == 4 || factorStage1 == 8),
              let commandQueue,
              let pipelineState,
              let inBufL = inputBufferL,
              let inBufR = inputBufferR,
              let outBufL = outputBufferL,
              let outBufR = outputBufferR,
              let weightsBuf = (factorStage1 == 2 ? weightsBufferR2 : (factorStage1 == 4 ? weightsBufferR4 : weightsBufferR8))
        else {
            return runCPUFallbackWithSyncedHistory(
                inputL: inputL,
                inputR: inputR,
                inputFrames: inputFrames,
                inputRateHz: inputRateHz,
                targetRateHz: targetRateHz,
                outputBuffer: outputBuffer
            )
        }

        if lastStage1Owner == .cpu {
            cpuFallback.exportStage1HistoryToDF64(dstHistL: histLPtr, dstHistR: histRPtr, dstCount: histCount)
        }

        // 1. Заполняем Shared-буфер [hist (taps-1) | новые отсчёты (inputFrames)] в формате df64.
        // Важно: НЕ обновляем histLPtr/histRPtr до успешного завершения GPU-команды, чтобы при сбое GPU
        // cpuFallback получил консистентную историю без двойного сдвига!
        let histLen = histCount
        let totalIn = histLen + inputFrames
        let inPtrL = inBufL.contents().bindMemory(to: SIMD2<Float>.self, capacity: totalIn)
        let inPtrR = inBufR.contents().bindMemory(to: SIMD2<Float>.self, capacity: totalIn)

        memcpy(inPtrL, histLPtr, histLen * MemoryLayout<SIMD2<Float>>.stride)
        memcpy(inPtrR, histRPtr, histLen * MemoryLayout<SIMD2<Float>>.stride)
        for i in 0..<inputFrames {
            inPtrL[histLen &+ i] = Self.doubleToDF64(inputL[i])
            inPtrR[histLen &+ i] = Self.doubleToDF64(inputR[i])
        }

        // 2. Диспетчеризация вычислительного шейдера на GPU Apple Silicon (внутри autoreleasepool без удержания ссылок)
        let dxdFrames = inputFrames * factorStage1
        let gpuSucceeded: Bool = autoreleasepool {
            guard let cmdBuf = commandQueue.makeCommandBufferWithUnretainedReferences() ?? commandQueue.makeCommandBuffer(),
                  let encoder = cmdBuf.makeComputeCommandEncoder() else {
                return false
            }

            var params = PolyphaseDispatchParams(
                inputFrames: UInt32(inputFrames),
                factor: UInt32(factorStage1),
                tapsPerPhase: UInt32(tapsPerPhase)
            )
            encoder.setComputePipelineState(pipelineState)
            encoder.setBuffer(inBufL, offset: 0, index: 0)
            encoder.setBuffer(inBufR, offset: 0, index: 1)
            encoder.setBuffer(weightsBuf, offset: 0, index: 2)
            encoder.setBuffer(outBufL, offset: 0, index: 3)
            encoder.setBuffer(outBufR, offset: 0, index: 4)
            encoder.setBytes(&params, length: MemoryLayout<PolyphaseDispatchParams>.stride, index: 5)

            let threadGroupWidth = min(pipelineState.maxTotalThreadsPerThreadgroup, 256)
            let gridSize = MTLSize(width: dxdFrames, height: 1, depth: 1)
            let groupSize = MTLSize(width: threadGroupWidth, height: 1, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: groupSize)
            encoder.endEncoding()

            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            return cmdBuf.status == .completed
        }

        if !gpuSucceeded {
            return runCPUFallbackWithSyncedHistory(
                inputL: inputL,
                inputR: inputR,
                inputFrames: inputFrames,
                inputRateHz: inputRateHz,
                targetRateHz: targetRateHz,
                outputBuffer: outputBuffer
            )
        }

        // GPU завершил Stage 1 успешно — фиксируем новую историю последних (tapsPerPhase - 1) элементов
        memcpy(histLPtr, inPtrL.advanced(by: inputFrames), histLen * MemoryLayout<SIMD2<Float>>.stride)
        memcpy(histRPtr, inPtrR.advanced(by: inputFrames), histLen * MemoryLayout<SIMD2<Float>>.stride)
        lastStage1Owner = .gpu

        // 3. Читаем результат Stage 1 (DXD 352.8 / 384 кГц) из Unified Memory в предвыделенный mlock-буфер dxdScratch (0 аллокаций!)
        let outPtrL = outBufL.contents().bindMemory(to: SIMD2<Float>.self, capacity: dxdFrames)
        let outPtrR = outBufR.contents().bindMemory(to: SIMD2<Float>.self, capacity: dxdFrames)

        if targetRateHz <= dxdRateHz {
            let count = min(dxdFrames, outputBuffer.capacityFrames)
            for i in 0..<count {
                outputBuffer.left[i] = Self.df64ToDouble(outPtrL[i])
                outputBuffer.right[i] = Self.df64ToDouble(outPtrR[i])
            }
            return count
        }

        let clampedDXD = min(dxdFrames, dxdScratch.capacityFrames)
        for i in 0..<clampedDXD {
            dxdScratch.left[i] = Self.df64ToDouble(outPtrL[i])
            dxdScratch.right[i] = Self.df64ToDouble(outPtrR[i])
        }

        // Stage 2A (HB63) + Stage 2B (HB31) + Stage 3 (Lagrange-5) всегда выполняются на cpuFallback с непрерывной историей DXD
        return cpuFallback.oversampleFromDXD(
            dxdL: dxdScratch.left,
            dxdR: dxdScratch.right,
            dxdFrames: clampedDXD,
            dxdRateHz: dxdRateHz,
            targetRateHz: targetRateHz,
            outputBuffer: outputBuffer
        )
    }

    // MARK: - Embedded Metal Source (`PolyphaseOverlapSave.metal`)

    private static let embeddedMetalSource = """
    #include <metal_stdlib>
    using namespace metal;

    typedef float2 df64;

    inline df64 df64_quick_two_sum(float a, float b) {
        #pragma clang fp reassociate(off)
        #pragma clang fp contract(off)
        float s = a + b;
        float z = s - a;
        float e = b - z;
        return df64(s, e);
    }

    inline df64 df64_two_sum(float a, float b) {
        #pragma clang fp reassociate(off)
        #pragma clang fp contract(off)
        float s = a + b;
        float v = s - a;
        float e = (a - (s - v)) + (b - v);
        return df64(s, e);
    }

    inline df64 df64_add(df64 a, df64 b) {
        #pragma clang fp reassociate(off)
        #pragma clang fp contract(off)
        df64 s = df64_two_sum(a.x, b.x);
        s.y += a.y + b.y;
        return df64_quick_two_sum(s.x, s.y);
    }

    inline df64 df64_mul(df64 a, df64 b) {
        #pragma clang fp reassociate(off)
        #pragma clang fp contract(off)
        float p = a.x * b.x;
        float e = fma(a.x, b.x, -p);
        e = fma(a.x, b.y, e);
        e = fma(a.y, b.x, e);
        return df64_quick_two_sum(p, e);
    }

    struct PolyphaseDispatchParams {
        uint inputFrames;
        uint factor;
        uint tapsPerPhase;
    };

    kernel void polyphase_fir_df64_stereo(
        device const df64* historyAndInputL [[buffer(0)]],
        device const df64* historyAndInputR [[buffer(1)]],
        device const df64* polyphaseWeights [[buffer(2)]],
        device df64* outDXDL                [[buffer(3)]],
        device df64* outDXDR                [[buffer(4)]],
        constant PolyphaseDispatchParams& params [[buffer(5)]],
        uint gid [[thread_position_in_grid]]
    ) {
        uint totalOutputs = params.inputFrames * params.factor;
        if (gid >= totalOutputs) {
            return;
        }

        uint inFrame = gid / params.factor;
        uint phase = gid % params.factor;
        uint taps = params.tapsPerPhase;

        device const df64* winL = historyAndInputL + inFrame;
        device const df64* winR = historyAndInputR + inFrame;
        device const df64* weights = polyphaseWeights + (phase * taps);

        df64 accL = df64(0.0f, 0.0f);
        df64 accR = df64(0.0f, 0.0f);

        for (uint k = 0; k < taps; ++k) {
            df64 w = weights[k];
            accL = df64_add(accL, df64_mul(winL[k], w));
            accR = df64_add(accR, df64_mul(winR[k], w));
        }

        outDXDL[gid] = accL;
        outDXDR[gid] = accR;
    }
    """
}
