#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_speed;
    float u_edge;
    float u_time;
};

struct fx_film_burn_out
{
    float4 frag [[color(0)]];
};

struct fx_film_burn_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float fbm(thread float2& p)
{
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++)
    {
        v += (a * fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875));
        p *= 2.099999904632568359375;
        a *= 0.5;
    }
    return v;
}

fragment fx_film_burn_out fx_film_burn(fx_film_burn_in in [[stage_in]], constant Params& _70 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_film_burn_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float t = _70.u_time * _70.u_speed;
    float de = fast::min(fast::min(in.v_uv.x, 1.0 - in.v_uv.x), fast::min(in.v_uv.y, 1.0 - in.v_uv.y));
    float in_edge = smoothstep(_70.u_edge, 0.0, de);
    float2 param = (in.v_uv * 6.0) + float2(t * 0.300000011920928955078125);
    float _113 = fbm(param);
    float burn_n = _113;
    float burn = (in_edge * ((burn_n * 1.5) + 0.300000011920928955078125)) * _70.u_intensity;
    float3 hot = float3(1.0, 0.980000019073486328125, 0.800000011920928955078125);
    float3 flame = float3(1.0, 0.4000000059604644775390625, 0.0500000007450580596923828125);
    float3 char_col = float3(0.0500000007450580596923828125, 0.0199999995529651641845703125, 0.0);
    float3 _140;
    if (burn < 0.4000000059604644775390625)
    {
        _140 = mix(col.xyz, hot, float3(burn / 0.4000000059604644775390625));
    }
    else
    {
        float3 _154;
        if (burn < 0.699999988079071044921875)
        {
            _154 = mix(hot, flame, float3((burn - 0.4000000059604644775390625) / 0.300000011920928955078125));
        }
        else
        {
            _154 = mix(flame, char_col, float3((burn - 0.699999988079071044921875) / 0.300000011920928955078125));
        }
        _140 = _154;
    }
    float3 fire = _140;
    float _178;
    if (burn > 0.949999988079071044921875)
    {
        _178 = 0.0;
    }
    else
    {
        _178 = col.w;
    }
    float alpha = _178;
    out.frag = float4(fast::clamp(fire, float3(0.0), float3(1.0)), alpha);
    return out;
}

