#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_cell_size;
    float u_border;
    float u_saturation;
};

struct fx_stained_glass_out
{
    float4 frag [[color(0)]];
};

struct fx_stained_glass_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_stained_glass_out fx_stained_glass(fx_stained_glass_in in [[stage_in]], constant Params& _30 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_stained_glass_out out = {};
    float2 uv_px = in.v_uv * float2(_30.u_tex_w, _30.u_tex_h);
    float2 cell_uv = uv_px / float2(_30.u_cell_size);
    float2 cell_id = floor(cell_uv);
    float min_d = 1000000000.0;
    float2 nearest = float2(0.0);
    for (int dy = -1; dy <= 1; dy++)
    {
        for (int dx = -1; dx <= 1; dx++)
        {
            float2 nb = cell_id + float2(float(dx), float(dy));
            float2 param = nb;
            float2 param_1 = nb + float2(13.69999980926513671875, 7.30000019073486328125);
            float2 jitter = float2(hash(param), hash(param_1));
            float2 pt = (nb + float2(0.5)) + ((jitter - float2(0.5)) * 0.699999988079071044921875);
            float d = length(cell_uv - pt);
            if (d < min_d)
            {
                min_d = d;
                nearest = pt;
            }
        }
    }
    float min_d2 = 1000000000.0;
    for (int dy_1 = -1; dy_1 <= 1; dy_1++)
    {
        for (int dx_1 = -1; dx_1 <= 1; dx_1++)
        {
            float2 nb_1 = cell_id + float2(float(dx_1), float(dy_1));
            float2 param_2 = nb_1;
            float2 param_3 = nb_1 + float2(13.69999980926513671875, 7.30000019073486328125);
            float2 jitter_1 = float2(hash(param_2), hash(param_3));
            float2 pt_1 = (nb_1 + float2(0.5)) + ((jitter_1 - float2(0.5)) * 0.699999988079071044921875);
            float d_1 = length(cell_uv - pt_1);
            if (d_1 > (min_d + 0.001000000047497451305389404296875))
            {
                min_d2 = fast::min(min_d2, d_1);
            }
        }
    }
    float border_mask = smoothstep(0.0, _30.u_border, min_d2 - min_d);
    float2 sample_uv = (nearest * _30.u_cell_size) / float2(_30.u_tex_w, _30.u_tex_h);
    float3 cell_col = u_tex.sample(u_texSmplr, fast::clamp(sample_uv, float2(0.0), float2(1.0))).xyz;
    float lum = dot(cell_col, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    cell_col = mix(float3(lum), cell_col, float3(_30.u_saturation));
    float3 result = cell_col * border_mask;
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), 1.0);
    return out;
}

