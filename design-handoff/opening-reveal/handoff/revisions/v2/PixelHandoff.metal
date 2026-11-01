#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

namespace {
    constant float cellPitch = 11.5;
    constant float gridEnd = 0.35;

    float4 averagedCell(SwiftUI::Layer layer, float2 center, float2 size) {
        // Five bounded taps retain a little of fine type without aliasing it
        // into a single high-contrast dot as the source becomes pixelated.
        float2 maximum = max(size - 0.5, float2(0.0));
        float2 spread = float2(cellPitch * 0.23);
        float4 color = float4(layer.sample(clamp(center, float2(0.0), maximum))) * 2.0;
        color += float4(layer.sample(clamp(center + float2(-spread.x, -spread.y), float2(0.0), maximum)));
        color += float4(layer.sample(clamp(center + float2( spread.x, -spread.y), float2(0.0), maximum)));
        color += float4(layer.sample(clamp(center + float2(-spread.x,  spread.y), float2(0.0), maximum)));
        color += float4(layer.sample(clamp(center + float2( spread.x,  spread.y), float2(0.0), maximum)));
        return color / 6.0;
    }
}

[[ stitchable ]] half4 pixelHandoff(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float progress
) {
    float p = clamp(progress, 0.0, 1.0);
    if (p <= 0.0) return half4(layer.sample(position));
    if (p >= 1.0) return half4(0.0);

    float2 cell = floor(position / cellPitch);
    float2 center = (cell + 0.5) * cellPitch;
    float2 local = fract(position / cellPitch) - 0.5;

    float4 original = float4(layer.sample(position));
    float4 pixel = averagedCell(layer, center, size);
    float formation = smoothstep(0.0, gridEnd, p);
    float4 result = mix(original, pixel, formation);

    // A fine charcoal boundary and miniature X make the individual pixels
    // legible on the dark tour. They sit over the pixel color, never punch
    // holes through it during the formation phase.
    float2 edge = 0.5 - abs(local);
    float gridLine = 1.0 - smoothstep(0.015, 0.095, min(edge.x, edge.y));
    float diagonal = min(abs(local.x - local.y), abs(local.x + local.y));
    float xMark = (1.0 - smoothstep(0.045, 0.085, diagonal))
        * (1.0 - smoothstep(0.32, 0.46, max(abs(local.x), abs(local.y))));
    float mark = max(gridLine * 0.75, xMark * 0.48);
    result.rgb = mix(result.rgb, float3(0.16), mark * formation * 0.48);

    if (p <= gridEnd) return half4(result);

    // The radius reaches the farthest corner plus a whole cell. A cell
    // shrinks within a narrow advancing band; elsewhere the edge remains a
    // crisp collection of square pixels instead of a blurred circle.
    float opening = (p - gridEnd) / (1.0 - gridEnd);
    float2 origin = size * 0.5;
    float2 reach = max(origin, size - origin);
    float farthest = length(reach);
    float radius = mix(-2.0 * cellPitch, farthest + 2.0 * cellPitch, opening);
    float distance = length(center - origin);
    float cellOpen = clamp((radius - distance) / cellPitch, 0.0, 1.0);
    float halfExtent = 0.5 * (1.0 - cellOpen);
    float shape = min(halfExtent - abs(local.x), halfExtent - abs(local.y));
    float alpha = cellOpen <= 0.0 ? 1.0
        : (cellOpen >= 1.0 ? 0.0 : smoothstep(-0.065, 0.02, shape));
    return half4(float4(result.rgb * alpha, result.a * alpha));
}
