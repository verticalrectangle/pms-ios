#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_h;
    float u_cold_hue;
    float u_hot_hue;
    float u_contrast;
    float u_scanlines;
};

struct fx_thermal_map_out
{
    float4 frag [[color(0)]];
};

struct fx_thermal_map_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_thermal_map_out fx_thermal_map(fx_thermal_map_in in [[stage_in]], constant Params& _67 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_thermal_map_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float heat = fast::clamp(((lum - 0.5) * _67.u_contrast) + 0.5, 0.0, 1.0);
    float3 thermal;
    if (heat < 0.25)
    {
        float param = _67.u_cold_hue;
        float param_1 = _67.u_cold_hue;
        thermal = mix(hue2rgb(param) * 0.300000011920928955078125, hue2rgb(param_1), float3(heat * 4.0));
    }
    else
    {
        if (heat < 0.5)
        {
            float param_2 = _67.u_cold_hue;
            float param_3 = mix(_67.u_cold_hue, 0.3300000131130218505859375, 1.0);
            thermal = mix(hue2rgb(param_2), hue2rgb(param_3), float3((heat - 0.25) * 4.0));
        }
        else
        {
            if (heat < 0.75)
            {
                float param_4 = 0.3300000131130218505859375;
                float param_5 = _67.u_hot_hue + 0.0500000007450580596923828125;
                thermal = mix(hue2rgb(param_4), hue2rgb(param_5), float3((heat - 0.5) * 4.0));
            }
            else
            {
                float param_6 = _67.u_hot_hue;
                thermal = mix(hue2rgb(param_6), float3(1.0, 1.0, 0.89999997615814208984375), float3((heat - 0.75) * 4.0));
            }
        }
    }
    float scan = 1.0 - ((_67.u_scanlines * 0.5) * (0.5 + (0.5 * sin((in.v_uv.y * _67.u_tex_h) * 3.141590118408203125))));
    out.frag = float4(fast::clamp(thermal * scan, float3(0.0), float3(1.0)), col.w);
    return out;
}

