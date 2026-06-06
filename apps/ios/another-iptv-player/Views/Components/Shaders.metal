#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexMain(uint vertexID [[vertex_id]]) {
    float4 positions[] = {
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0),
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0)
    };
    
    float2 texCoords[] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                               texture2d<float> texture [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    return texture.sample(s, in.texCoord);
}

// TODO: Optimized YUV fragment shader for production
fragment float4 yuvFragmentMain(VertexOut in [[stage_in]],
                                  texture2d<float> textureY [[texture(0)]],
                                  texture2d<float> textureUV [[texture(1)]]) {
    // Standard BT.709 YUV to RGB conversion
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float y = textureY.sample(s, in.texCoord).r;
    float2 uv = textureUV.sample(s, in.texCoord).rg - 0.5;
    
    float4 color;
    color.r = y + 1.402 * uv.y;
    color.g = y - 0.3441 * uv.x - 0.7141 * uv.y;
    color.b = y + 1.772 * uv.x;
    color.a = 1.0;
    
    return color;
}
