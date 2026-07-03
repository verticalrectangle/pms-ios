#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_threshold;
    float u_length;
    float u_intensity;
};

struct fx_anamorphic_streak_out
{
    float4 frag [[color(0)]];
};

struct fx_anamorphic_streak_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_anamorphic_streak_out fx_anamorphic_streak(fx_anamorphic_streak_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_anamorphic_streak_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float px = 1.0 / _25.u_tex_w;
    float3 streak = float3(0.0);
    float total = 0.001000000047497451305389404296875;
    for (int i = 1; i <= 80; i++)
    {
        float off = float(i) * px;
        if (off > _25.u_length)
        {
            break;
        }
        float wt = exp(((-off) / _25.u_length) * 5.0);
        float3 r = u_tex.sample(u_texSmplr, fast::clamp(float2(in.v_uv.x + off, in.v_uv.y), float2(0.0), float2(1.0))).xyz;
        float3 l = u_tex.sample(u_texSmplr, fast::clamp(float2(in.v_uv.x - off, in.v_uv.y), float2(0.0), float2(1.0))).xyz;
        float br = fast::max(r.x, fast::max(r.y, r.z));
        float bl = fast::max(l.x, fast::max(l.y, l.z));
        float mr = step(_25.u_threshold, br);
        float ml = step(_25.u_threshold, bl);
        streak += (((r * mr) + (l * ml)) * wt);
        total += ((mr + ml) * wt);
    }
    streak /= float3(total);
    float3 anam = (streak * float3(0.300000011920928955078125, 0.699999988079071044921875, 1.5)) * _25.u_intensity;
    out.frag = float4(fast::clamp(col.xyz + anam, float3(0.0), float3(1.5)), col.w);
    return out;
}

