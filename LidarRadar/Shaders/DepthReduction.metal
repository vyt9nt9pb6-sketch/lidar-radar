#include <metal_stdlib>
using namespace metal;

// 與 MetalDepthReducer.swift 的 DepthParams 欄位順序、型別必須完全一致。
// 深度圖每像素一個 float（公尺）。這裡做平行最小值，不做 CPU 逐像素迴圈。
struct DepthParams {
    uint width;
    uint height;
    uint roiMinX;
    uint roiMaxX;
    uint roiMinY;
    uint roiMaxY;
    uint minConfidence;
    uint useConfidence;
    uint depthStride;
    uint confidenceStride;
    uint groupsX;
    float minValidDistance;
    float maxValidDistance;
    uint pad0;
    uint pad1;
    uint pad2;
};

struct FinalizeParams {
    uint count;
    uint pad0;
    uint pad1;
    uint pad2;
};

// Swift 端以 16×16 派送，線性執行緒數必須是 256。
constant uint kThreadgroupSize = 256;

/// 每個 threadgroup 在中央視區裡找最小深度，寫進 partialMins。
kernel void depthPartialMin(
    device const float *depth [[buffer(0)]],
    device const uchar *confidence [[buffer(1)]],
    device float *partialMins [[buffer(2)]],
    constant DepthParams &params [[buffer(3)]],
    uint2 gid [[thread_position_in_grid]],
    uint tgIndex [[thread_index_in_threadgroup]],
    uint2 tgid [[threadgroup_position_in_grid]]
) {
    threadgroup float localMins[kThreadgroupSize];

    float value = INFINITY;

    bool inside = gid.x < params.width && gid.y < params.height
        && gid.x >= params.roiMinX && gid.x < params.roiMaxX
        && gid.y >= params.roiMinY && gid.y < params.roiMaxY;

    if (inside) {
        float d = depth[gid.y * params.depthStride + gid.x];
        bool confidenceOK = true;
        if (params.useConfidence != 0) {
            uint c = uint(confidence[gid.y * params.confidenceStride + gid.x]);
            confidenceOK = c >= params.minConfidence;
        }
        // 用範圍比較同時排除 NaN、0、以及光達可靠距離外的雜訊。
        if (confidenceOK && d >= params.minValidDistance && d <= params.maxValidDistance) {
            value = d;
        }
    }

    localMins[tgIndex] = value;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = kThreadgroupSize >> 1; stride > 0; stride >>= 1) {
        if (tgIndex < stride) {
            localMins[tgIndex] = min(localMins[tgIndex], localMins[tgIndex + stride]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (tgIndex == 0) {
        partialMins[tgid.y * params.groupsX + tgid.x] = localMins[0];
    }
}

/// 把每個 threadgroup 的最小值再收成一個數，寫入 result[0]。
kernel void depthFinalizeMin(
    device const float *partialMins [[buffer(0)]],
    device float *result [[buffer(1)]],
    constant FinalizeParams &params [[buffer(2)]],
    uint tgIndex [[thread_index_in_threadgroup]]
) {
    threadgroup float localMins[kThreadgroupSize];

    float value = INFINITY;
    for (uint index = tgIndex; index < params.count; index += kThreadgroupSize) {
        value = min(value, partialMins[index]);
    }

    localMins[tgIndex] = value;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint stride = kThreadgroupSize >> 1; stride > 0; stride >>= 1) {
        if (tgIndex < stride) {
            localMins[tgIndex] = min(localMins[tgIndex], localMins[tgIndex + stride]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (tgIndex == 0) {
        result[0] = localMins[0];
    }
}
