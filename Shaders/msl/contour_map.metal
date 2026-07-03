#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_levels;
    float u_line_width;
    float u_line_hue;
    float u_fill_sat;
};

struct fx_contour_map_out
{
    float4 frag [[color(0)]];
};

struct fx_contour_map_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_contour_map_out fx_contour_map(fx_contour_map_in in [[stage_in]], constant Params& _65 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_contour_map_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float level0 = floor(lum * _65.u_levels) / _65.u_levels;
    float level_frac = fract(lum * _65.u_levels);
    float line = smoothstep(_65.u_line_width, 0.0, fast::min(level_frac, 1.0 - level_frac));
    float fill_hue = mix(0.670000016689300537109375, 0.0, level0);
    float param = fill_hue;
    float3 fill_col = mix(float3(level0), hue2rgb(param), float3(_65.u_fill_sat));
    fill_col *= (0.300000011920928955078125 + (0.699999988079071044921875 * level0));
    float param_1 = _65.u_line_hue;
    float3 line_col = hue2rgb(param_1) * 0.800000011920928955078125;
    float3 result = mix(fill_col, line_col, float3(line));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

