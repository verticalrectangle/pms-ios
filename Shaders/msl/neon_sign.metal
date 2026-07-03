#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_edge_str;
    float u_glow_radius;
    float u_hue_shift;
    float u_bg_darken;
};

struct fx_neon_sign_out
{
    float4 frag [[color(0)]];
};

struct fx_neon_sign_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float sobel_lum(texture2d<float> tex, sampler texSmplr, thread const float2& uv, thread const float2& px, thread float& gx, thread float& gy)
{
    float k0 = dot(tex.sample(texSmplr, (uv + (float2(-1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k1 = dot(tex.sample(texSmplr, (uv + (float2(0.0, -1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k2 = dot(tex.sample(texSmplr, (uv + (float2(1.0, -1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k3 = dot(tex.sample(texSmplr, (uv + (float2(-1.0, 0.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k5 = dot(tex.sample(texSmplr, (uv + (float2(1.0, 0.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k6 = dot(tex.sample(texSmplr, (uv + (float2(-1.0, 1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k7 = dot(tex.sample(texSmplr, (uv + (float2(0.0, 1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float k8 = dot(tex.sample(texSmplr, (uv + (float2(1.0) * px))).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    gx = (((((-k0) + k2) - (2.0 * k3)) + (2.0 * k5)) - k6) + k8;
    gy = (((((-k0) - (2.0 * k1)) - k2) + k6) + (2.0 * k7)) + k8;
    return dot(tex.sample(texSmplr, uv).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
}

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_neon_sign_out fx_neon_sign(fx_neon_sign_in in [[stage_in]], constant Params& _179 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_neon_sign_out out = {};
    float2 px = float2(1.0 / _179.u_tex_w, 1.0 / _179.u_tex_h);
    float2 param = in.v_uv;
    float2 param_1 = px;
    float param_2;
    float param_3;
    float _202 = sobel_lum(u_tex, u_texSmplr, param, param_1, param_2, param_3);
    float gx = param_2;
    float gy = param_3;
    float edge = fast::clamp(sqrt((gx * gx) + (gy * gy)) * _179.u_edge_str, 0.0, 1.0);
    float edge_angle = ((precise::atan2(gy, gx) / 6.28318023681640625) + 0.5) + _179.u_hue_shift;
    float param_4 = edge_angle;
    float3 edge_col = hue2rgb(param_4);
    float3 glow = float3(0.0);
    float wsum = 0.0;
    float param_7;
    float param_8;
    for (int ri = 1; ri <= 8; ri++)
    {
        float r = (float(ri) * _179.u_glow_radius) * 0.125;
        float w = exp(((-r) * r) / (((_179.u_glow_radius * _179.u_glow_radius) * 0.1500000059604644775390625) + 0.001000000047497451305389404296875));
        for (int di = 0; di < 8; di++)
        {
            float a = float(di) * 0.785399973392486572265625;
            float2 offset = float2(cos(a), sin(a)) * r;
            float2 uv2 = fast::clamp(in.v_uv + (offset * px), float2(0.0), float2(1.0));
            float2 param_5 = uv2;
            float2 param_6 = px;
            float _313 = sobel_lum(u_tex, u_texSmplr, param_5, param_6, param_7, param_8);
            float gx2 = param_7;
            float gy2 = param_8;
            float e2 = fast::clamp((sqrt((gx2 * gx2) + (gy2 * gy2)) * _179.u_edge_str) * 0.60000002384185791015625, 0.0, 1.0);
            float angle2 = ((precise::atan2(gy2, gx2) / 6.28318023681640625) + 0.5) + _179.u_hue_shift;
            float param_9 = angle2;
            glow += ((hue2rgb(param_9) * e2) * w);
            wsum += w;
        }
    }
    glow /= float3(wsum + 0.001000000047497451305389404296875);
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    float3 bg = orig.xyz * (1.0 - (_179.u_bg_darken * 0.85000002384185791015625));
    float3 result = float3(1.0) - ((float3(1.0) - bg) * (float3(1.0) - (glow * 3.0)));
    result = mix(result, edge_col, float3(edge * 0.85000002384185791015625));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), orig.w);
    return out;
}

