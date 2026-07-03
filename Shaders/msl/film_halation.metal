#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_threshold;
    float u_radius;
    float u_red_shift;
    float u_strength;
};

struct fx_film_halation_out
{
    float4 frag [[color(0)]];
};

struct fx_film_halation_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_film_halation_out fx_film_halation(fx_film_halation_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_film_halation_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    float3 halo = float3(0.0);
    float wsum = 0.0;
    int R = int(_13.u_radius);
    int _52 = -R;
    for (int dy = _52; dy <= R; dy++)
    {
        int _64 = -R;
        for (int dx = _64; dx <= R; dx++)
        {
            float w = exp((-float((dx * dx) + (dy * dy))) / ((_13.u_radius * _13.u_radius) + 0.001000000047497451305389404296875));
            float4 s = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(float(dx), float(dy)) * px), float2(0.0), float2(1.0)));
            float bright = smoothstep(_13.u_threshold, _13.u_threshold + 0.20000000298023223876953125, dot(s.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625)));
            halo += ((s.xyz * bright) * w);
            wsum += w;
        }
    }
    halo /= float3(wsum + 0.001000000047497451305389404296875);
    halo *= mix(float3(1.0), float3(1.5, 0.5, 0.20000000298023223876953125), float3(_13.u_red_shift));
    float3 result = float3(1.0) - ((float3(1.0) - orig.xyz) * (float3(1.0) - ((halo * _13.u_strength) * 0.800000011920928955078125)));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), orig.w);
    return out;
}

