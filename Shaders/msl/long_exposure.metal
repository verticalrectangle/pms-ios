#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_threshold;
    float u_trail;
    float u_glow;
};

struct fx_long_exposure_out
{
    float4 frag [[color(0)]];
};

struct fx_long_exposure_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_long_exposure_out fx_long_exposure(fx_long_exposure_in in [[stage_in]], constant Params& _35 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_long_exposure_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 px = float2(1.0 / _35.u_tex_w, 1.0 / _35.u_tex_h);
    float3 streak = float3(0.0);
    float wsum = 0.0;
    for (int i = 1; i <= 16; i++)
    {
        float fi = float(i);
        float w = exp((-fi) * _35.u_trail);
        float step_px = fi * 5.0;
        streak += (u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(step_px, 0.0) * px), float2(0.0), float2(1.0))).xyz * w);
        streak += (u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(step_px, 0.0) * px), float2(0.0), float2(1.0))).xyz * w);
        streak += (u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(0.0, step_px) * px), float2(0.0), float2(1.0))).xyz * w);
        streak += (u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(0.0, step_px) * px), float2(0.0), float2(1.0))).xyz * w);
        wsum += (4.0 * w);
    }
    streak /= float3(wsum);
    float bright_mask = smoothstep(_35.u_threshold - 0.100000001490116119384765625, _35.u_threshold + 0.25, lum);
    float3 result = float3(1.0) - ((float3(1.0) - col.xyz) * (float3(1.0) - (((streak * bright_mask) * _35.u_glow) * 1.5)));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

