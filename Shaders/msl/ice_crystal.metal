#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_scale;
    float u_refract;
    float u_tint;
};

struct fx_ice_crystal_out
{
    float4 frag [[color(0)]];
};

struct fx_ice_crystal_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_ice_crystal_out fx_ice_crystal(fx_ice_crystal_in in [[stage_in]], constant Params& _30 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_ice_crystal_out out = {};
    float2 uv_sc = (in.v_uv * float2(_30.u_tex_w, _30.u_tex_h)) / float2(_30.u_scale);
    float2 cell = floor(uv_sc);
    float2 local = fract(uv_sc);
    float min_d1 = 1000000000.0;
    float min_d2 = 1000000000.0;
    float2 nearest = float2(0.0);
    for (int dy = -1; dy <= 1; dy++)
    {
        for (int dx = -1; dx <= 1; dx++)
        {
            float2 nb = cell + float2(float(dx), float(dy));
            float2 param = nb;
            float2 param_1 = nb + float2(17.299999237060546875, 43.700000762939453125);
            float2 pt = float2(hash(param), hash(param_1));
            float d = length((((local - nb) + cell) - nb) + pt);
            d = length((fract(uv_sc) - pt) - float2(float(dx), float(dy)));
            if (d < min_d1)
            {
                min_d2 = min_d1;
                min_d1 = d;
                nearest = pt;
            }
            else
            {
                if (d < min_d2)
                {
                    min_d2 = d;
                }
            }
        }
    }
    float border_dist = min_d2 - min_d1;
    float border = smoothstep(0.0500000007450580596923828125, 0.0, border_dist);
    float2 refract_dir = fast::normalize(in.v_uv - (((cell + nearest) * _30.u_scale) / float2(_30.u_tex_w, _30.u_tex_h)));
    float2 refract_uv = fast::clamp(in.v_uv + ((refract_dir * border) * _30.u_refract), float2(0.0), float2(1.0));
    float3 sample_col = u_tex.sample(u_texSmplr, refract_uv).xyz;
    float3 ice_tint = mix(sample_col, sample_col * float3(0.699999988079071044921875, 0.85000002384185791015625, 1.2000000476837158203125), float3(_30.u_tint));
    ice_tint += (float3(0.800000011920928955078125, 0.89999997615814208984375, 1.0) * (border * 0.5));
    out.frag = float4(fast::clamp(ice_tint, float3(0.0), float3(1.0)), 1.0);
    return out;
}

