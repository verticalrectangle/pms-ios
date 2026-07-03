#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_depth;
    float u_rotation;
    float u_zoom;
    float u_time;
};

struct fx_mirror_tunnel_out
{
    float4 frag [[color(0)]];
};

struct fx_mirror_tunnel_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_mirror_tunnel_out fx_mirror_tunnel(fx_mirror_tunnel_in in [[stage_in]], constant Params& _21 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_mirror_tunnel_out out = {};
    float2 uv = in.v_uv - float2(0.5);
    int maxSteps = int(_21.u_depth);
    float angle_acc = (_21.u_time * _21.u_rotation) * 0.5;
    for (int i = 0; i < 12; i++)
    {
        if (i >= maxSteps)
        {
            break;
        }
        float s = sin(angle_acc);
        float c_a = cos(angle_acc);
        uv = float2((uv.x * c_a) - (uv.y * s), (uv.x * s) + (uv.y * c_a));
        uv /= float2(_21.u_zoom);
        uv = abs((fract((uv * 0.5) + float2(0.5)) * 2.0) - float2(1.0)) - float2(0.5);
        angle_acc += (0.20000000298023223876953125 + (_21.u_rotation * 0.300000011920928955078125));
    }
    uv += float2(0.5);
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    return out;
}

