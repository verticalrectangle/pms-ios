#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_flow;
    float u_scale;
    float u_speed;
};

struct fx_liquid_marble_out
{
    float4 frag [[color(0)]];
};

struct fx_liquid_marble_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float n2(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

static inline __attribute__((always_inline))
float _noise(thread const float2& p)
{
    float2 i = floor(p);
    float2 f = fract(p);
    f = (f * f) * (float2(3.0) - (f * 2.0));
    float2 param = i;
    float2 param_1 = i + float2(1.0, 0.0);
    float2 param_2 = i + float2(0.0, 1.0);
    float2 param_3 = i + float2(1.0);
    return mix(mix(n2(param), n2(param_1), f.x), mix(n2(param_2), n2(param_3), f.x), f.y);
}

fragment fx_liquid_marble_out fx_liquid_marble(fx_liquid_marble_in in [[stage_in]], constant Params& _81 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_liquid_marble_out out = {};
    float t = (_81.u_time * _81.u_speed) * 0.4000000059604644775390625;
    float2 p = in.v_uv * _81.u_scale;
    float2 param = p + float2(0.0, t);
    float2 param_1 = p + float2(5.19999980926513671875, t * 1.2999999523162841796875);
    float2 q = float2(_noise(param), _noise(param_1));
    float2 param_2 = (p + (q * 4.0)) + float2(1.7000000476837158203125, 9.19999980926513671875 - t);
    float2 param_3 = (p + (q * 4.0)) + float2(8.30000019073486328125, 2.7999999523162841796875 + t);
    float2 r = float2(_noise(param_2), _noise(param_3));
    float2 warp = (((q - float2(0.5)) + ((r - float2(0.5)) * 0.699999988079071044921875)) * 0.119999997317790985107421875) * _81.u_flow;
    float4 c = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + warp, float2(0.0), float2(1.0)));
    float vein = smoothstep(0.3499999940395355224609375, 0.0, abs(r.x - r.y));
    float4 _194 = c;
    float3 _196 = _194.xyz * (1.0 - ((vein * 0.25) * _81.u_flow));
    c.x = _196.x;
    c.y = _196.y;
    c.z = _196.z;
    out.frag = c;
    return out;
}

