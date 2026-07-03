#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_intensity;
    float u_decay;
    float u_cx;
    float u_cy;
};

struct fx_god_rays_out
{
    float4 frag [[color(0)]];
};

struct fx_god_rays_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_god_rays_out fx_god_rays(fx_god_rays_in in [[stage_in]], constant Params& _24 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_god_rays_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 src = float2(_24.u_cx, _24.u_cy);
    float2 delta = (in.v_uv - src) / float2(16.0);
    float2 uv = in.v_uv;
    float3 rays = float3(0.0);
    float illum = 1.0;
    for (int i = 0; i < 16; i++)
    {
        uv -= delta;
        float3 s = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0))).xyz;
        float bright = dot(s, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
        rays += ((s * fast::max(bright - 0.300000011920928955078125, 0.0)) * illum);
        illum *= _24.u_decay;
    }
    rays /= float3(16.0);
    out.frag = float4(fast::clamp(col.xyz + (rays * _24.u_intensity), float3(0.0), float3(1.0)), col.w);
    return out;
}

