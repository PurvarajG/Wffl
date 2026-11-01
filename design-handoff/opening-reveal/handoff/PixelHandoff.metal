#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

namespace {
    constant float cellPitch = 58.0;
    constant float gridEnd = 0.30;
}

[[ stitchable ]] half4 pixelHandoff(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress
) {
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.0) return layer.sample(position);
    if (p >= 1.0) return half4(0.0);

    float2 tileIndex = floor(position / cellPitch);
    float2 center = (tileIndex + 0.5) * cellPitch;
    float2 local = position - center;
    float formation = smoothstep(0.0, gridEnd, p);
    half4 original = layer.sample(position);

    if (p <= gridEnd) {
        // The screen stays intact inside each tile. Only the narrow, opaque
        // cut line appears as progress advances toward the opening.
        float edge = cellPitch * 0.5 - max(abs(local.x), abs(local.y));
        float seam = 1.0 - smoothstep(0.05, 0.55, edge);
        if (seam <= 0.0) return original;
        float4 result = float4(original);
        result.rgb *= 1.0 - seam * formation * 0.52;
        return half4(result);
    }

    float2 origin = size * 0.5;
    float2 halfSize = max(origin, float2(1.0));
    float2 firstCenter = float2(cellPitch * 0.5);
    float2 lastCenter = (floor(max(size - 0.001, float2(0.0)) / cellPitch) + 0.5) * cellPitch;
    float2 cornerDistance = max(abs(firstCenter - origin), abs(lastCenter - origin)) / halfSize;
    float farthest = max(cornerDistance.x, cornerDistance.y);
    float2 tileDistance = abs(center - origin) / halfSize;
    float distance = max(tileDistance.x, tileDistance.y);

    // The moving square front is about four tile widths deep. A tile stays
    // in place while its contents and square outline recede toward its own
    // center. The same progress value redraws exactly in either direction.
    float band = min(0.85, 4.0 * cellPitch / min(halfSize.x, halfSize.y));
    float opening = (p - gridEnd) / (1.0 - gridEnd);
    float front = opening * (farthest + band);
    float tileOpen = smoothstep(0.0, 1.0, (front - distance) / band);
    if (tileOpen >= 1.0) return half4(0.0);

    float scale = 1.0 - tileOpen;
    float shape = cellPitch * 0.5 * scale - max(abs(local.x), abs(local.y));
    float alpha = tileOpen <= 0.0 ? 1.0 : smoothstep(-0.7, 0.4, shape);
    if (alpha <= 0.0) return half4(0.0);

    float2 mapped = clamp(
        center + local / max(scale, 0.01),
        center - cellPitch * 0.5,
        center + cellPitch * 0.5
    );
    float2 maximum = max(size - 0.5, float2(0.0));
    float4 block = float4(layer.sample(clamp(mapped, float2(0.0), maximum)));

    // Cut lines travel with the original image as each tile shrinks.
    float mappedEdge = cellPitch * 0.5 - max(abs(mapped.x - center.x), abs(mapped.y - center.y));
    float seam = 1.0 - smoothstep(0.05, 0.55, mappedEdge);
    block.rgb *= 1.0 - seam * 0.52;
    return half4(block * alpha);
}
