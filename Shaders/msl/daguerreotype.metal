#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tone;
    float u_vignette;
    float u_scratch;
    float u_time;
};

struct fx_daguerreotype_out
{
    float4 frag [[color(0)]];
};

struct fx_daguerreotype_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_daguerreotype_out fx_daguerreotype(fx_daguerreotype_in in [[stage_in]], constant Params& _73 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_daguerreotype_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    lum = fast::clamp(((lum - 0.5) * 1.39999997615814208984375) + 0.5, 0.0, 1.0);
    float3 warm = float3(0.85000002384185791015625, 0.75, 0.550000011920928955078125);
    float3 cool = float3(0.699999988079071044921875, 0.75, 0.85000002384185791015625);
    float3 toned = mix(cool * lum, warm * lum, float3(_73.u_tone));
    float2 d = (in.v_uv - float2(0.5)) * float2(1.0, 1.2999999523162841796875);
    float vig = 1.0 - (smoothstep(0.25, 0.75, length(d)) * _73.u_vignette);
    toned *= vig;
    float2 param = float2(floor(in.v_uv.x * 400.0) / 400.0, _73.u_time * 0.100000001490116119384765625);
    float scratch_n = hash(param);
    float scratch = step(1.0 - (_73.u_scratch * 0.039999999105930328369140625), scratch_n) * smoothstep(0.4000000059604644775390625, 0.60000002384185791015625, in.v_uv.y);
    toned += float3(scratch * 0.4000000059604644775390625);
    float2 param_1 = in.v_uv * 500.0;
    float plate = (hash(param_1) * 0.039999999105930328369140625) - 0.0199999995529651641845703125;
    out.frag = float4(fast::clamp(toned + float3(plate), float3(0.0), float3(1.0)), col.w);
    return out;
}

