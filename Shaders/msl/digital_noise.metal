#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_intensity;
    float u_color_sep;
    float u_luma_bias;
    float u_time;
};

struct fx_digital_noise_out
{
    float4 frag [[color(0)]];
};

struct fx_digital_noise_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_digital_noise_out fx_digital_noise(fx_digital_noise_in in [[stage_in]], constant Params& _40 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_digital_noise_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 npx = floor(in.v_uv * float2(_40.u_tex_w, _40.u_tex_h));
    float lum = dot(col.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float noise_scale = mix(1.0, 1.0 - lum, _40.u_luma_bias) * _40.u_intensity;
    float2 param = npx + float2(_40.u_time * 0.300000011920928955078125, 0.0);
    float nr = (hash(param) - 0.5) * noise_scale;
    float2 param_1 = (npx + float2(0.0, _40.u_time * 0.4000000059604644775390625)) + float2(31.700000762939453125, 71.3000030517578125);
    float ng = (hash(param_1) - 0.5) * noise_scale;
    float2 param_2 = (npx + float2(_40.u_time * 0.5)) + float2(97.09999847412109375, 13.69999980926513671875);
    float nb_n = (hash(param_2) - 0.5) * noise_scale;
    float2 param_3 = npx + float2(_40.u_time * 0.3499999940395355224609375, _40.u_time * 0.25);
    float luma_noise = (hash(param_3) - 0.5) * noise_scale;
    float3 _noise = mix(float3(luma_noise), float3(nr, ng, nb_n), float3(_40.u_color_sep));
    out.frag = float4(fast::clamp(col.xyz + _noise, float3(0.0), float3(1.0)), col.w);
    return out;
}

