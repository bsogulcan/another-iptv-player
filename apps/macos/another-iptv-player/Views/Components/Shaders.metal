#include <metal_stdlib>
using namespace metal;

// Aspect-aware video display shader.
// Uniforms paketi: vertex shader full-screen quad çizer; her vertex texCoord'u
// view aspect'ine göre cropping/letterboxing yapacak şekilde transform edilir.

struct VideoUniforms {
    // Scale uygulanır: <1 ise content küçülür (letterbox); 1 ise tam doldurur.
    float2 scale;
    // Texture rect içinde sample offset (fill modunda crop için).
    float2 texOffset;
    float2 texScale;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]],
                            constant VideoUniforms& uniforms [[buffer(0)]]) {
    // Triangle strip: 4 köşe, full-screen quad.
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0),  // bottom-left (texture upside-down vs NDC)
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    VertexOut out;
    out.position = float4(positions[vertexID] * uniforms.scale, 0.0, 1.0);
    out.texCoord = texCoords[vertexID] * uniforms.texScale + uniforms.texOffset;
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return tex.sample(s, in.texCoord);
}
