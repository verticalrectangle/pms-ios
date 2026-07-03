#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_dot_size;
    float u_scatter;
};

struct fx_pointillist_out
{
    float4 frag [[color(0)]];
};

struct fx_pointillist_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_pointillist_out fx_pointillist(fx_pointillist_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_pointillist_out out = {};
    float2 px = float2(1.0 / _28.u_tex_w, 1.0 / _28.u_tex_h);
    float sz = _28.u_dot_size;
    float2 cell_uv = in.v_uv / (px * sz);
    float2 cell_id = floor(cell_uv);
    float3 result = float3(0.949999988079071044921875);
    float min_dist = 1000000000.0;
    float3 nearest_col = float3(0.5);
    for (int dy = -1; dy <= 1; dy++)
    {
        for (int dx = -1; dx <= 1; dx++)
        {
            float2 nb = cell_id + float2(float(dx), float(dy));
            float2 param = nb;
            float2 param_1 = nb + float2(31.700000762939453125, 71.3000030517578125);
            float2 jitter = float2(hash(param), hash(param_1));
            float2 dot_ctr = (((nb + float2(0.5)) + ((jitter - float2(0.5)) * _28.u_scatter)) * px) * sz;
            float d = length(in.v_uv - dot_ctr);
            if (d < min_dist)
            {
                min_dist = d;
                float3 col = u_tex.sample(u_texSmplr, fast::clamp(dot_ctr, float2(0.0), float2(1.0))).xyz;
                float lum = dot(col, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
                float r = (((1.0 - (lum * 0.699999988079071044921875)) * px.x) * sz) * 0.550000011920928955078125;
                nearest_col = select(float3(0.949999988079071044921875), col, bool3(d < r));
            }
        }
    }
    float lum_c = dot(nearest_col, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 best_center = ((floor(in.v_uv / (px * sz)) + float2(0.5)) * px) * sz;
    float3 cell_color = u_tex.sample(u_texSmplr, fast::clamp(best_center, float2(0.0), float2(1.0))).xyz;
    float cell_lum = dot(cell_color, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float r_1 = (((1.0 - (cell_lum * 0.699999988079071044921875)) * px.x) * sz) * 0.550000011920928955078125;
    float2 local = in.v_uv - best_center;
    result = select(float3(0.949999988079071044921875), cell_color, bool3(length(local) < r_1));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), 1.0);
    return out;
}

