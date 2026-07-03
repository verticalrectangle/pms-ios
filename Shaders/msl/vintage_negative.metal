#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_orange_mask;
    float u_contrast;
    float u_grain;
    float u_time;
};

struct fx_vintage_negative_out
{
    float4 frag [[color(0)]];
};

struct fx_vintage_negative_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float hash(thread const float2& p)
{
    return fract(sin(dot(p, float2(127.09999847412109375, 311.70001220703125))) * 43758.546875);
}

fragment fx_vintage_negative_out fx_vintage_negative(fx_vintage_negative_in in [[stage_in]], constant Params& _57 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_vintage_negative_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float3 neg = float3(1.0) - col.xyz;
    neg.x = mix(neg.x, (neg.x * 0.85000002384185791015625) + 0.1500000059604644775390625, _57.u_orange_mask);
    neg.y = mix(neg.y, (neg.y * 0.699999988079071044921875) + 0.07999999821186065673828125, _57.u_orange_mask);
    neg.z = mix(neg.z, (neg.z * 0.300000011920928955078125) + 0.0199999995529651641845703125, _57.u_orange_mask * 0.800000011920928955078125);
    neg = fast::clamp(((neg - float3(0.5)) * _57.u_contrast) + float3(0.5), float3(0.0), float3(1.0));
    float2 npx = floor(in.v_uv * float2(_57.u_tex_w, _57.u_tex_h));
    float2 param = npx + float2(_57.u_time * 23.1000003814697265625, _57.u_time * 17.700000762939453125);
    float g = ((hash(param) - 0.5) * _57.u_grain) * 0.300000011920928955078125;
    out.frag = float4(fast::clamp(neg + float3(g), float3(0.0), float3(1.0)), col.w);
    return out;
}

