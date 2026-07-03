#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_intensity;
    float u_color_mix;
    float u_time;
};

struct fx_tv_static_out
{
    float4 frag [[color(0)]];
};

struct fx_tv_static_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_tv_static_out fx_tv_static(fx_tv_static_in in [[stage_in]], constant Params& _40 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_tv_static_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 npx = floor((in.v_uv * float2(_40.u_tex_w, _40.u_tex_h)) / float2(2.0)) * 2.0;
    float2 param = npx + fract(float2(_40.u_time * 37.40000152587890625, _40.u_time * 23.1000003814697265625));
    float n = hash(param);
    float2 param_1 = (npx * 0.5) + fract(float2(_40.u_time * 11.69999980926513671875, _40.u_time * 41.299999237060546875));
    float n2 = hash(param_1);
    float3 grey_static = float3(n);
    float2 param_2 = (npx + float2(50.0)) + float2(fract(_40.u_time * 19.299999237060546875));
    float3 color_static = float3(n, n2, hash(param_2));
    float3 static_col = mix(grey_static, color_static, float3(_40.u_color_mix));
    float3 result = mix(col.xyz, static_col, float3(_40.u_intensity));
    float roll = fract(_40.u_time * 0.07999999821186065673828125);
    float bar = smoothstep(0.0199999995529651641845703125, 0.0, abs(in.v_uv.y - roll)) * 0.300000011920928955078125;
    result = mix(result, float3(1.0), float3(bar));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col.w);
    return out;
}

