#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_focus_y;
    float u_focus_band;
    float u_blur_radius;
    float u_saturation;
};

struct fx_tilt_shift_out
{
    float4 frag [[color(0)]];
};

struct fx_tilt_shift_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_tilt_shift_out fx_tilt_shift(fx_tilt_shift_in in [[stage_in]], constant Params& _19 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_tilt_shift_out out = {};
    float dist = abs(in.v_uv.y - _19.u_focus_y);
    float blur_t = smoothstep(_19.u_focus_band, _19.u_focus_band + 0.25, dist);
    float maxOff = (_19.u_blur_radius * 0.004999999888241291046142578125) * blur_t;
    float o1 = maxOff * 0.25;
    float o2 = maxOff * 0.5;
    float o3 = maxOff * 0.75;
    float o4 = maxOff;
    float o5 = maxOff * 1.33000004291534423828125;
    float4 c = u_tex.sample(u_texSmplr, in.v_uv);
    float4 y1 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.0, o1), float2(0.0), float2(1.0)));
    float4 y2 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(0.0, o1), float2(0.0), float2(1.0)));
    float4 y3 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.0, o2), float2(0.0), float2(1.0)));
    float4 y4 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(0.0, o2), float2(0.0), float2(1.0)));
    float4 y5 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.0, o3), float2(0.0), float2(1.0)));
    float4 y6 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(0.0, o3), float2(0.0), float2(1.0)));
    float4 y7 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.0, o4), float2(0.0), float2(1.0)));
    float4 y8 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(0.0, o4), float2(0.0), float2(1.0)));
    float4 y9 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(0.0, o5), float2(0.0), float2(1.0)));
    float4 yA = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(0.0, o5), float2(0.0), float2(1.0)));
    float4 blurred = (((((c * 0.20000000298023223876953125) + ((y1 + y2) * 0.17000000178813934326171875)) + ((y3 + y4) * 0.12999999523162841796875)) + ((y5 + y6) * 0.0900000035762786865234375)) + ((y7 + y8) * 0.0599999986588954925537109375)) + ((y9 + yA) * 0.039999999105930328369140625);
    blurred /= float4(1.17999994754791259765625);
    float4 orig = u_tex.sample(u_texSmplr, in.v_uv);
    float4 mixed = mix(orig, blurred, float4(blur_t));
    float lum = dot(mixed.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float4 _233 = mixed;
    float3 _239 = mix(float3(lum), _233.xyz, float3(_19.u_saturation));
    mixed.x = _239.x;
    mixed.y = _239.y;
    mixed.z = _239.z;
    out.frag = float4(fast::clamp(mixed.xyz, float3(0.0), float3(1.0)), mixed.w);
    return out;
}

