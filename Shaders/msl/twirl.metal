#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_strength;
    float u_radius;
};

struct fx_twirl_out
{
    float4 frag [[color(0)]];
};

struct fx_twirl_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_twirl_out fx_twirl(fx_twirl_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_twirl_out out = {};
    float2 c = float2(0.5);
    float2 d = in.v_uv - c;
    float dist = length(d);
    float angle = _25.u_strength * smoothstep(_25.u_radius, 0.0, dist);
    float cs = cos(angle);
    float sn = sin(angle);
    float2 rot = float2((cs * d.x) - (sn * d.y), (sn * d.x) + (cs * d.y));
    out.frag = u_tex.sample(u_texSmplr, fast::clamp(rot + c, float2(0.0), float2(1.0)));
    return out;
}

