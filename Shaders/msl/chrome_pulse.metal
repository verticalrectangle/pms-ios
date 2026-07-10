#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_time;
    float u_chrome;
    float u_pulse;
    float u_edge;
};

struct fx_chrome_pulse_out
{
    float4 frag [[color(0)]];
};

struct fx_chrome_pulse_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_chrome_pulse_out fx_chrome_pulse(fx_chrome_pulse_in in [[stage_in]], constant Params& _13 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_chrome_pulse_out out = {};
    float2 px = float2(1.0 / _13.u_tex_w, 1.0 / _13.u_tex_h);
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(c.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float m = 0.5 + (0.5 * sin((lum * 12.0) - 1.5));
    m = mix(lum, m * smoothstep(0.0500000007450580596923828125, 0.89999997615814208984375, lum), 0.85000002384185791015625);
    float3 chrome = float3(m) * float3(0.85000002384185791015625, 0.920000016689300537109375, 1.0499999523162841796875);
    float l1 = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(px.x * 2.0, 0.0))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float l2 = dot(u_tex.sample(u_texSmplr, (in.v_uv + float2(0.0, px.y * 2.0))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float edge = fast::clamp(abs(lum - l1) + abs(lum - l2), 0.0, 1.0) * 4.0;
    float beat = 0.60000002384185791015625 + (0.4000000059604644775390625 * sin((_13.u_time * _13.u_pulse) * 2.0));
    float3 glow = ((float3(0.4000000059604644775390625, 0.800000011920928955078125, 1.0) * edge) * _13.u_edge) * beat;
    float3 rgb = mix(c.xyz, chrome, float3(_13.u_chrome)) + glow;
    out.frag = float4(fast::clamp(rgb, float3(0.0), float3(1.0)), c.w);
    return out;
}

