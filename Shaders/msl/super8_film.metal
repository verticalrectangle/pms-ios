#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_grain;
    float u_gate;
    float u_fade;
    float u_time;
};

struct fx_super8_film_out
{
    float4 frag [[color(0)]];
};

struct fx_super8_film_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_super8_film_out fx_super8_film(fx_super8_film_in in [[stage_in]], constant Params& _28 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_super8_film_out out = {};
    float weave = (sin(_28.u_time * 12.0) * 0.008000000379979610443115234375) * _28.u_gate;
    float weave_y = (cos(_28.u_time * 7.30000019073486328125) * 0.004999999888241291046142578125) * _28.u_gate;
    float2 uv = in.v_uv + float2(weave, weave_y);
    float4 col = u_tex.sample(u_texSmplr, fast::clamp(uv, float2(0.0), float2(1.0)));
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float3 warm = (col.xyz * float3(1.10000002384185791015625, 0.980000019073486328125, 0.800000011920928955078125)) + float3(_28.u_fade * 0.119999997317790985107421875, _28.u_fade * 0.0500000007450580596923828125, 0.0);
    warm = mix(warm, warm + (float3(0.07999999821186065673828125, 0.0599999986588954925537109375, 0.039999999105930328369140625) * _28.u_fade), float3(smoothstep(0.300000011920928955078125, 0.0, lum)));
    float2 param = (uv * 800.0) + float2(fract(_28.u_time * 24.0));
    float grain = ((hash(param) - 0.5) * _28.u_grain) * 0.119999997317790985107421875;
    warm += float3(grain);
    float frame_v = smoothstep(0.0, 0.039999999105930328369140625, in.v_uv.y) * smoothstep(1.0, 0.959999978542327880859375, in.v_uv.y);
    float frame_h = smoothstep(0.0, 0.02999999932944774627685546875, in.v_uv.x) * smoothstep(1.0, 0.9700000286102294921875, in.v_uv.x);
    warm *= (frame_v * frame_h);
    out.frag = float4(fast::clamp(warm, float3(0.0), float3(1.0)), col.w);
    return out;
}

