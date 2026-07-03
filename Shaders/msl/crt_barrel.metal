#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_h;
    float u_distort;
    float u_corner_dark;
    float u_rgb_shift;
    float u_scanline;
};

struct fx_crt_barrel_out
{
    float4 frag [[color(0)]];
};

struct fx_crt_barrel_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float2 barrel(thread const float2& uv, thread const float& k)
{
    float2 cc = uv - float2(0.5);
    float r2 = dot(cc, cc);
    return uv + (cc * (r2 * k));
}

fragment fx_crt_barrel_out fx_crt_barrel(fx_crt_barrel_in in [[stage_in]], constant Params& _38 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_crt_barrel_out out = {};
    float2 param = in.v_uv;
    float param_1 = _38.u_distort * 0.60000002384185791015625;
    float2 uv = barrel(param, param_1);
    bool _56 = uv.x < 0.0;
    bool _64;
    if (!_56)
    {
        _64 = uv.x > 1.0;
    }
    else
    {
        _64 = _56;
    }
    bool _72;
    if (!_64)
    {
        _72 = uv.y < 0.0;
    }
    else
    {
        _72 = _64;
    }
    bool _79;
    if (!_72)
    {
        _79 = uv.y > 1.0;
    }
    else
    {
        _79 = _72;
    }
    if (_79)
    {
        out.frag = float4(0.0, 0.0, 0.0, 1.0);
        return out;
    }
    float2 param_2 = in.v_uv + float2(_38.u_rgb_shift, 0.0);
    float param_3 = _38.u_distort * 0.60000002384185791015625;
    float2 uvR = barrel(param_2, param_3);
    float2 param_4 = in.v_uv + float2(-_38.u_rgb_shift, 0.0);
    float param_5 = _38.u_distort * 0.60000002384185791015625;
    float2 uvB = barrel(param_4, param_5);
    float r = u_tex.sample(u_texSmplr, fast::clamp(uvR, float2(0.0), float2(1.0))).x;
    float g = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).y;
    float b = u_tex.sample(u_texSmplr, fast::clamp(uvB, float2(0.0), float2(1.0))).z;
    float3 col = float3(r, g, b);
    float scan = 1.0 - ((_38.u_scanline * 0.5) * (0.5 + (0.5 * sin((uv.y * _38.u_tex_h) * 3.141590118408203125))));
    col *= scan;
    float2 cc = uv - float2(0.5);
    float vig = 1.0 - (dot(cc * 1.60000002384185791015625, cc * 1.60000002384185791015625) * _38.u_corner_dark);
    out.frag = float4(fast::clamp(col * vig, float3(0.0), float3(1.0)), 1.0);
    return out;
}

