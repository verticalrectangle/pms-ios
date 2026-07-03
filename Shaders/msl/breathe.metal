#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_time;
    float u_strength;
    float u_breathe_rate;
    float u_warp_strength;
    float u_color_speed;
    float u_chroma_split;
    float u_complexity;
};

struct fx_breathe_out
{
    float4 frag [[color(0)]];
};

struct fx_breathe_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float3 rgb2hsv(thread const float3& c)
{
    float4 K = float4(0.0, -0.3333333432674407958984375, 0.666666686534881591796875, -1.0);
    float4 p = mix(float4(c.zy, K.wz), float4(c.yz, K.xy), float4(step(c.z, c.y)));
    float4 q = mix(float4(p.xyw, c.x), float4(c.x, p.yzx), float4(step(p.x, c.x)));
    float d = q.x - fast::min(q.w, q.y);
    return float3(abs(q.z + ((q.w - q.y) / ((6.0 * d) + 1.0000000133514319600180897396058e-10))), d / (q.x + 1.0000000133514319600180897396058e-10), q.x);
}

static inline __attribute__((always_inline))
float3 hsv2rgb(thread const float3& c)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    float3 p = abs((fract(c.xxx + K.xyz) * 6.0) - K.www);
    return mix(K.xxx, fast::clamp(p - K.xxx, float3(0.0), float3(1.0)), float3(c.y)) * c.z;
}

fragment fx_breathe_out fx_breathe(fx_breathe_in in [[stage_in]], constant Params& _177 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_breathe_out out = {};
    float4 src = u_tex.sample(u_texSmplr, in.v_uv);
    float lum = dot(src.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float2 grad = float2(dfdx(lum), dfdy(lum));
    if (_177.u_complexity > 0.00999999977648258209228515625)
    {
        float2 px = float2(1.0) * (_177.u_complexity * 0.0040000001899898052215576171875);
        float lum2 = dot(u_tex.sample(u_texSmplr, (in.v_uv + px)).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
        float lum3 = dot(u_tex.sample(u_texSmplr, (in.v_uv - px)).xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
        float2 wide_grad = float2(dfdx(lum2 - lum3), dfdy(lum2 - lum3));
        grad = mix(grad, wide_grad, float2(_177.u_complexity));
    }
    float edge_mag = fast::clamp(length(grad) * 4.0, 0.0, 1.0);
    float2 edge_norm = fast::normalize(grad + float2(9.9999999747524270787835121154785e-07));
    float t = _177.u_time * _177.u_breathe_rate;
    float breath = sin(t * 6.283199787139892578125) * _177.u_warp_strength;
    float breath2 = (sin((t * 10.16639995574951171875) + 0.89999997615814208984375) * _177.u_warp_strength) * 0.25;
    float pulse = breath + breath2;
    float2 edge_warp = (edge_norm * edge_mag) * pulse;
    float2 base_warp = ((float2(sin((in.v_uv.y * 5.0) + (t * 1.2999999523162841796875)), cos((in.v_uv.x * 4.19999980926513671875) + (t * 1.10000002384185791015625))) * _177.u_warp_strength) * 0.07999999821186065673828125) * (1.0 - edge_mag);
    float2 warp = edge_warp + base_warp;
    float split = (_177.u_chroma_split * _177.u_warp_strength) * 0.60000002384185791015625;
    float2 uv_r = fast::clamp((in.v_uv + warp) + (edge_norm * split), float2(0.0), float2(1.0));
    float2 uv_g = fast::clamp(in.v_uv + warp, float2(0.0), float2(1.0));
    float2 uv_b = fast::clamp((in.v_uv + warp) - (edge_norm * split), float2(0.0), float2(1.0));
    float3 col = float3(u_tex.sample(u_texSmplr, uv_r).x, u_tex.sample(u_texSmplr, uv_g).y, u_tex.sample(u_texSmplr, uv_b).z);
    float a = u_tex.sample(u_texSmplr, uv_g).w;
    float3 param = col;
    float3 hsv = rgb2hsv(param);
    float hue_shift = ((_177.u_time * _177.u_color_speed) * 0.07999999821186065673828125) + ((edge_mag * _177.u_color_speed) * 0.039999999105930328369140625);
    hsv.x = fract(hsv.x + (hue_shift * hsv.z));
    hsv.y = fast::clamp(hsv.y * (1.0 + (0.3499999940395355224609375 * _177.u_color_speed)), 0.0, 1.0);
    float3 param_1 = hsv;
    col = hsv2rgb(param_1);
    out.frag = float4(mix(src.xyz, col, float3(_177.u_strength)), a);
    return out;
}

