#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_intensity;
    float u_hue;
    float u_glow;
};

struct fx_color_dodge_out
{
    float4 frag [[color(0)]];
};

struct fx_color_dodge_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_color_dodge_out fx_color_dodge(fx_color_dodge_in in [[stage_in]], constant Params& _31 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_color_dodge_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 kp = abs((fract(float3(_31.u_hue) + K.xyz) * 6.0) - K.www);
    float3 dodge_col = fast::clamp(kp - K.xxx, float3(0.0), float3(1.0));
    float3 dodged = col.xyz / fast::max(float3(1.0) - (dodge_col * _31.u_intensity), float3(0.001000000047497451305389404296875));
    dodged = fast::clamp(dodged, float3(0.0), float3(1.0));
    float2 px = float2(1.0 / _31.u_tex_w, 1.0 / _31.u_tex_h);
    float3 bloom = float3(0.0);
    for (int i = 1; i <= 4; i++)
    {
        float r = float(i) * 3.0;
        bloom += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(r, 0.0) * px), float2(0.0), float2(1.0))).xyz;
        bloom += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(r, 0.0) * px), float2(0.0), float2(1.0))).xyz;
        bloom += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + (float2(0.0, r) * px), float2(0.0), float2(1.0))).xyz;
        bloom += u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - (float2(0.0, r) * px), float2(0.0), float2(1.0))).xyz;
    }
    bloom /= float3(16.0);
    float3 result = mix(dodged, float3(1.0) - ((float3(1.0) - dodged) * (float3(1.0) - ((bloom * dodge_col) * _31.u_glow))), float3(0.5));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

