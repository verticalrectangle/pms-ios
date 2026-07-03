#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_density;
    float u_speed;
    float u_green_mix;
    float u_time;
};

struct fx_matrix_rain_out
{
    float4 frag [[color(0)]];
};

struct fx_matrix_rain_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_matrix_rain_out fx_matrix_rain(fx_matrix_rain_in in [[stage_in]], constant Params& _41 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_matrix_rain_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float col_w = 12.0 / _41.u_tex_w;
    float col_id = floor(in.v_uv.x / col_w);
    float2 param = float2(col_id, 0.0);
    float col_phase = hash(param);
    float drop_speed = _41.u_speed * (0.5 + (col_phase * 1.5));
    float drop_y = fract(col_phase + ((_41.u_time * drop_speed) * 0.1500000059604644775390625));
    float dist_to_head = in.v_uv.y - drop_y;
    float rain = 0.0;
    if ((dist_to_head > 0.0) && (dist_to_head < 0.3499999940395355224609375))
    {
        float head = exp((-dist_to_head) * 12.0);
        rain = head * step(col_phase, _41.u_density);
    }
    float head_flash = exp((-abs(in.v_uv.y - drop_y)) * 60.0) * step(col_phase, _41.u_density);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 green_tint = float3(lum * 0.20000000298023223876953125, lum, lum * 0.300000011920928955078125);
    float3 base = mix(col.xyz, green_tint, float3(_41.u_green_mix));
    float3 rain_col = float3(0.0, rain * 0.800000011920928955078125, 0.0) + float3(head_flash * 0.800000011920928955078125, head_flash, head_flash * 0.800000011920928955078125);
    out.frag = float4(fast::clamp(base + rain_col, float3(0.0), float3(1.0)), col.w);
    return out;
}

