#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

// Implementation of the GLSL mod() function, which is slightly different than Metal fmod()
template<typename Tx, typename Ty>
inline Tx mod(Tx x, Ty y)
{
    return x - y * floor(x / y);
}

struct Params
{
    float u_tex_h;
    float u_curvature;
    float u_glow;
};

struct fx_crt_out
{
    float4 frag [[color(0)]];
};

struct fx_crt_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_crt_out fx_crt(fx_crt_in in [[stage_in]], constant Params& _27 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_crt_out out = {};
    float2 p = (in.v_uv * 2.0) - float2(1.0);
    p += ((((p * p.yx) * p.yx) * _27.u_curvature) * 0.300000011920928955078125);
    float2 warped = (p * 0.5) + float2(0.5);
    bool _51 = warped.x < 0.0;
    bool _58;
    if (!_51)
    {
        _58 = warped.x > 1.0;
    }
    else
    {
        _58 = _51;
    }
    bool _66;
    if (!_58)
    {
        _66 = warped.y < 0.0;
    }
    else
    {
        _66 = _58;
    }
    bool _73;
    if (!_66)
    {
        _73 = warped.y > 1.0;
    }
    else
    {
        _73 = _66;
    }
    if (_73)
    {
        out.frag = float4(0.0, 0.0, 0.0, 1.0);
        return out;
    }
    float4 col = u_tex.sample(u_texSmplr, warped);
    float line = mod(warped.y * _27.u_tex_h, 2.0);
    float scan = mix(1.0, 0.64999997615814208984375, step(1.0, line));
    float4 _105 = col;
    float3 _107 = _105.xyz * scan;
    col.x = _107.x;
    col.y = _107.y;
    col.z = _107.z;
    float4 _115 = col;
    float4 _125 = col;
    float3 _127 = _125.xyz + ((_115.xyz * _27.u_glow) * float3(0.0500000007450580596923828125, 0.1500000059604644775390625, 0.0500000007450580596923828125));
    col.x = _127.x;
    col.y = _127.y;
    col.z = _127.z;
    float2 edge = smoothstep(float2(0.0), float2(0.0500000007450580596923828125), warped) * smoothstep(float2(1.0), float2(0.949999988079071044921875), warped);
    float4 _150 = col;
    float3 _152 = _150.xyz * (edge.x * edge.y);
    col.x = _152.x;
    col.y = _152.y;
    col.z = _152.z;
    out.frag = col;
    return out;
}

