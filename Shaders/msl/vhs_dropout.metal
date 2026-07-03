#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_h;
    float u_density;
    float u_strength;
    float u_speed;
    float u_time;
};

struct fx_vhs_dropout_out
{
    float4 frag [[color(0)]];
};

struct fx_vhs_dropout_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_vhs_dropout_out fx_vhs_dropout(fx_vhs_dropout_in in [[stage_in]], constant Params& _45 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_vhs_dropout_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float scan = floor(in.v_uv.y * _45.u_tex_h);
    float frame = floor((_45.u_time * _45.u_speed) * 15.0);
    float2 param = float2(scan, frame);
    float drop_r = hash(param);
    float2 param_1 = float2(scan * 0.5, frame + 1.0);
    float drop_r2 = hash(param_1);
    float dropout = step(1.0 - _45.u_density, drop_r) * _45.u_strength;
    float3 result = mix(col.xyz, float3(1.0), float3(dropout));
    if (dropout > 0.0)
    {
        float shift = (drop_r2 - 0.5) * 0.039999999105930328369140625;
        result.x = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(shift, 0.0), float2(0.0), float2(1.0))).x;
        result.z = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(shift, 0.0), float2(0.0), float2(1.0))).z;
    }
    out.frag = float4(result, col.w);
    return out;
}

