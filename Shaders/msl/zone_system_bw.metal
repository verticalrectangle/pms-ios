#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_zones;
    float u_contrast;
    float u_grain;
    float u_paper_white;
    float u_time;
};

struct fx_zone_system_bw_out
{
    float4 frag [[color(0)]];
};

struct fx_zone_system_bw_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_zone_system_bw_out fx_zone_system_bw(fx_zone_system_bw_in in [[stage_in]], constant Params& _51 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_zone_system_bw_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    lum = fast::clamp(((lum - 0.5) * _51.u_contrast) + 0.5, 0.0, 1.0);
    lum = floor(lum * _51.u_zones) / (_51.u_zones - 1.0);
    float2 npx = floor(in.v_uv * float2(_51.u_tex_w, _51.u_tex_h));
    float shadow_grain = 1.5 - lum;
    float2 param = npx + float2(_51.u_time * 17.299999237060546875, _51.u_time * 31.1000003814697265625);
    float g = (((hash(param) - 0.5) * _51.u_grain) * 0.3499999940395355224609375) * shadow_grain;
    lum = fast::clamp(lum + g, 0.0, 1.0);
    float3 result = mix(float3(0.039999999105930328369140625, 0.0350000001490116119384765625, 0.02999999932944774627685546875), float3(_51.u_paper_white, _51.u_paper_white * 0.9900000095367431640625, _51.u_paper_white * 0.959999978542327880859375), float3(lum));
    out.frag = float4(result, col.w);
    return out;
}

