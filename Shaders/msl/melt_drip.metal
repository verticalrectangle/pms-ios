#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_melt;
    float u_drip;
    float u_haze;
};

struct fx_melt_drip_out
{
    float4 frag [[color(0)]];
};

struct fx_melt_drip_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float& n)
{
    return fract(sin(n) * 43758.546875);
}

static inline __attribute__((always_inline))
float _noise1(thread const float& x)
{
    float i = floor(x);
    float f = fract(x);
    f = (f * f) * (3.0 - (2.0 * f));
    float param = i;
    float param_1 = i + 1.0;
    return mix(hash(param), hash(param_1), f);
}

fragment fx_melt_drip_out fx_melt_drip(fx_melt_drip_in in [[stage_in]], constant Params& _61 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_melt_drip_out out = {};
    float param = (in.v_uv.x * (8.0 + (_61.u_drip * 30.0))) + (_61.u_time * 0.300000011920928955078125);
    float col = _noise1(param);
    float front = powr(in.v_uv.y, 1.5);
    float sag = ((_61.u_melt * 0.25) * col) * front;
    float2 uv = in.v_uv;
    uv.y = fast::clamp(uv.y - sag, 0.0, 1.0);
    uv.x += ((sin((uv.y * 60.0) + (_61.u_time * 5.0)) * 0.0040000001899898052215576171875) * _61.u_haze);
    float4 c = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    float4 _153 = c;
    float3 _155 = _153.xyz + ((float3(0.100000001490116119384765625, 0.039999999105930328369140625, 0.0) * (sag / fast::max(0.25 * _61.u_melt, 9.9999997473787516355514526367188e-05))) * _61.u_melt);
    c.x = _155.x;
    c.y = _155.y;
    c.z = _155.z;
    out.frag = fast::clamp(c, float4(0.0), float4(1.0));
    return out;
}

