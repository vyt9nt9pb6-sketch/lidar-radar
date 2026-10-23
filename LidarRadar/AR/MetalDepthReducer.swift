import ARKit
import CoreVideo
import Foundation
import Metal
import os

/// 把光達深度圖整批複製到 GPU，用 compute shader 取前方中央區域的最小距離。
///
/// 不做 CPU 逐像素迴圈。複製是一整塊 memcpy，最小值在 GPU 平行算完。
/// 呼叫端必須保證同一時間只有一個 ingest／reduce，因為緩衝區會重複使用。
final class MetalDepthReducer {
    struct SetupError: Error, LocalizedError, CustomStringConvertible {
        let description: String
        var errorDescription: String? { description }
    }

    /// 與 DepthReduction.metal 的 DepthParams 保持相同記憶體排列。
    struct DepthParams {
        var width: UInt32
        var height: UInt32
        var roiMinX: UInt32
        var roiMaxX: UInt32
        var roiMinY: UInt32
        var roiMaxY: UInt32
        var minConfidence: UInt32
        var useConfidence: UInt32
        var depthStride: UInt32
        var confidenceStride: UInt32
        var groupsX: UInt32
        var minValidDistance: Float
        var maxValidDistance: Float
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
        var pad2: UInt32 = 0
    }

    struct FinalizeParams {
        var count: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
        var pad2: UInt32 = 0
    }

    /// 必須與 shader 的 kThreadgroupSize、16×16 派送一致。
    static let threadgroupWidth = 16
    static let threadgroupHeight = 16
    static let threadgroupSize = 256

    /// 中央約四成寬、五成高。深度圖中心就是相機光軸，手機怎麼轉都對準背面正前方。
    static let roiMinX: Float = 0.30
    static let roiMaxX: Float = 0.70
    static let roiMinY: Float = 0.25
    static let roiMaxY: Float = 0.75
    /// ARConfidenceLevel.medium。低信心（玻璃、吸光表面）不拿來報警。
    static let minimumConfidence: UInt32 = 1
    static let minimumMeters: Float = 0.15
    static let maximumMeters: Float = 6

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let partialPipeline: MTLComputePipelineState
    private let finalizePipeline: MTLComputePipelineState
    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "metal")

    private var depthBuffer: MTLBuffer?
    private var confidenceBuffer: MTLBuffer?
    private var partialBuffer: MTLBuffer?
    private var resultBuffer: MTLBuffer?
    private var latestParams = DepthParams(
        width: 0,
        height: 0,
        roiMinX: 0,
        roiMaxX: 0,
        roiMinY: 0,
        roiMaxY: 0,
        minConfidence: minimumConfidence,
        useConfidence: 0,
        depthStride: 0,
        confidenceStride: 0,
        groupsX: 0,
        minValidDistance: minimumMeters,
        maxValidDistance: maximumMeters
    )
    private var loggedFormatMismatch = false

    init() throws {
        assert(MemoryLayout<DepthParams>.size == 64)
        assert(MemoryLayout<DepthParams>.stride == 64)
        assert(Self.threadgroupWidth * Self.threadgroupHeight == Self.threadgroupSize)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SetupError(description: L10n.failureNoMetal)
        }
        guard let queue = device.makeCommandQueue() else {
            throw SetupError(description: L10n.failureNoQueue)
        }
        guard let library = device.makeDefaultLibrary() else {
            throw SetupError(description: L10n.failureNoLibrary)
        }
        guard let partial = library.makeFunction(name: "depthPartialMin"),
              let finalize = library.makeFunction(name: "depthFinalizeMin") else {
            throw SetupError(description: L10n.failureNoKernel)
        }

        self.device = device
        self.queue = queue
        queue.label = "com.kwok.lidarradar.depth"
        let partialPipeline = try device.makeComputePipelineState(function: partial)
        let finalizePipeline = try device.makeComputePipelineState(function: finalize)
        guard partialPipeline.maxTotalThreadsPerThreadgroup >= Self.threadgroupSize,
              finalizePipeline.maxTotalThreadsPerThreadgroup >= Self.threadgroupSize else {
            throw SetupError(description: L10n.failureThreads)
        }
        self.partialPipeline = partialPipeline
        self.finalizePipeline = finalizePipeline
        assert(MemoryLayout<FinalizeParams>.stride == 16)
        resultBuffer = device.makeBuffer(length: MemoryLayout<Float>.stride, options: .storageModeShared)
        resultBuffer?.label = "depth-min"
    }

    /// ARKit 路徑。不要把 ARFrame 留到這個函式結束之後。
    func ingest(depthData: ARDepthData) -> Bool {
        ingest(depthMap: depthData.depthMap, confidenceMap: depthData.confidenceMap)
    }

    /// 把深度圖整塊複製進 GPU 緩衝。AVFoundation 的光達路徑沒有 ARKit 的信心圖時，傳 nil。
    func ingest(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?) -> Bool {
        let depthFormat = CVPixelBufferGetPixelFormatType(depthMap)
        guard depthFormat == kCVPixelFormatType_DepthFloat32 else {
            if !loggedFormatMismatch {
                loggedFormatMismatch = true
                logger.error("深度圖格式不是 DepthFloat32：\(depthFormat, privacy: .public)")
            }
            return false
        }
        guard let copied = copy(
            pixelBuffer: depthMap,
            elementSize: MemoryLayout<Float>.size,
            into: &depthBuffer,
            label: "depth"
        ) else {
            return false
        }

        var useConfidence: UInt32 = 0
        var confidenceStride = 0
        if let confidenceMap,
           CVPixelBufferGetPixelFormatType(confidenceMap) == kCVPixelFormatType_OneComponent8,
           CVPixelBufferGetWidth(confidenceMap) == copied.width,
           CVPixelBufferGetHeight(confidenceMap) == copied.height,
           let confidenceCopy = copy(
               pixelBuffer: confidenceMap,
               elementSize: 1,
               into: &confidenceBuffer,
               label: "confidence"
           ) {
            useConfidence = 1
            confidenceStride = confidenceCopy.stride
        } else if confidenceBuffer == nil {
            confidenceBuffer = device.makeBuffer(length: 256, options: .storageModeShared)
        }

        let groupsX = (copied.width + Self.threadgroupWidth - 1) / Self.threadgroupWidth
        let groupsY = (copied.height + Self.threadgroupHeight - 1) / Self.threadgroupHeight
        guard groupsX > 0, groupsY > 0 else { return false }

        latestParams.width = UInt32(copied.width)
        latestParams.height = UInt32(copied.height)
        latestParams.roiMinX = UInt32(Float(copied.width) * Self.roiMinX)
        latestParams.roiMaxX = max(latestParams.roiMinX + 1, UInt32(Float(copied.width) * Self.roiMaxX))
        latestParams.roiMinY = UInt32(Float(copied.height) * Self.roiMinY)
        latestParams.roiMaxY = max(latestParams.roiMinY + 1, UInt32(Float(copied.height) * Self.roiMaxY))
        latestParams.minConfidence = Self.minimumConfidence
        latestParams.useConfidence = useConfidence
        latestParams.depthStride = UInt32(copied.stride)
        latestParams.confidenceStride = UInt32(confidenceStride)
        latestParams.groupsX = UInt32(groupsX)
        latestParams.minValidDistance = Self.minimumMeters
        latestParams.maxValidDistance = Self.maximumMeters

        let partialBytes = groupsX * groupsY * MemoryLayout<Float>.size
        if partialBuffer == nil || (partialBuffer?.length ?? 0) < partialBytes {
            partialBuffer = device.makeBuffer(length: max(partialBytes, 256), options: .storageModeShared)
            partialBuffer?.label = "partial-mins"
        }
        return partialBuffer != nil && resultBuffer != nil
    }

    /// 在背景佇列呼叫。waitUntilCompleted 只擋住這條背景佇列，不擋主執行緒。
    /// 回傳公尺；無限大或失敗時回 nil。
    func reduce() -> Double? {
        guard let depthBuffer, let confidenceBuffer, let partialBuffer, let resultBuffer else {
            return nil
        }
        guard let commandBuffer = queue.makeCommandBuffer() else { return nil }
        commandBuffer.label = "depth-min"

        guard let partialEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        partialEncoder.label = "depth-partial"
        partialEncoder.setComputePipelineState(partialPipeline)
        partialEncoder.setBuffer(depthBuffer, offset: 0, index: 0)
        partialEncoder.setBuffer(confidenceBuffer, offset: 0, index: 1)
        partialEncoder.setBuffer(partialBuffer, offset: 0, index: 2)
        var params = latestParams
        partialEncoder.setBytes(&params, length: MemoryLayout<DepthParams>.stride, index: 3)

        let groupsX = Int(params.groupsX)
        let groupsY = (Int(params.height) + Self.threadgroupHeight - 1) / Self.threadgroupHeight
        partialEncoder.dispatchThreadgroups(
            MTLSize(width: groupsX, height: groupsY, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.threadgroupWidth, height: Self.threadgroupHeight, depth: 1)
        )
        partialEncoder.endEncoding()

        guard let finalizeEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        finalizeEncoder.label = "depth-finalize"
        finalizeEncoder.setComputePipelineState(finalizePipeline)
        finalizeEncoder.setBuffer(partialBuffer, offset: 0, index: 0)
        finalizeEncoder.setBuffer(resultBuffer, offset: 0, index: 1)
        var finalize = FinalizeParams(count: UInt32(groupsX * groupsY))
        finalizeEncoder.setBytes(&finalize, length: MemoryLayout<FinalizeParams>.stride, index: 2)
        finalizeEncoder.dispatchThreadgroups(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: Self.threadgroupSize, height: 1, depth: 1)
        )
        finalizeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            logger.error("Metal 命令失敗，status=\(commandBuffer.status.rawValue, privacy: .public)")
            return nil
        }

        let pointer = resultBuffer.contents().bindMemory(to: Float.self, capacity: 1)
        let meters = pointer.pointee
        guard meters.isFinite, meters > 0 else { return nil }
        return Double(meters)
    }

    private struct CopyResult {
        let width: Int
        let height: Int
        let stride: Int
    }

    private func copy(
        pixelBuffer: CVPixelBuffer,
        elementSize: Int,
        into buffer: inout MTLBuffer?,
        label: String
    ) -> CopyResult? {
        guard !CVPixelBufferIsPlanar(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, elementSize > 0, bytesPerRow >= width * elementSize,
              bytesPerRow % elementSize == 0 else {
            return nil
        }
        let stride = bytesPerRow / elementSize
        let totalBytes = stride * height * elementSize

        if buffer == nil || (buffer?.length ?? 0) < totalBytes {
            buffer = device.makeBuffer(length: max(totalBytes, 4096), options: .storageModeShared)
            buffer?.label = label
        }
        guard let buffer else { return nil }

        let lockFlags = CVPixelBufferLockFlags.readOnly
        guard CVPixelBufferLockBaseAddress(pixelBuffer, lockFlags) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, lockFlags) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        buffer.contents().copyMemory(from: base, byteCount: totalBytes)
        return CopyResult(width: width, height: height, stride: stride)
    }
}
