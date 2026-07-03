#pragma clang diagnostic ignored "-Wmissing-prototypes"

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_hue1;
    float u_hue2;
    float u_dot_size;
    float u_misreg;
    float u_paper;
};

struct fx_risograph_out
{
    float4 frag [[color(0)]];
};

struct fx_risograph_in
{
    float2 v_uv [[user(locn0)]];
};

static inline __attribute__((always_inline))
float halftone(thread const float2& uv, thread const float& scale, thread const float& angle, thread const float& density)
{
    float s = sin(angle);
    float c_a = cos(angle);
    float2 rot = float2((uv.x * c_a) - (uv.y * s), (uv.x * s) + (uv.y * c_a));
    float2 cell = fract(rot * scale) - float2(0.5);
    return smoothstep((density * 0.5) + 0.0500000007450580596923828125, (density * 0.5) - 0.0500000007450580596923828125, length(cell));
}

static inline __attribute__((always_inline))
float3 hue2rgb(thread const float& h)
{
    float4 K = float4(1.0, 0.666666686534881591796875, 0.3333333432674407958984375, 3.0);
    return fast::clamp(abs((fract(float3(h) + K.xyz) * 6.0) - K.www) - K.xxx, float3(0.0), float3(1.0));
}

fragment fx_risograph_out fx_risograph(fx_risograph_in in [[stage_in]], constant Params& _111 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_risograph_out out = {};
    float4 col1 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv + float2(_111.u_misreg, _111.u_misreg * 0.5), float2(0.0), float2(1.0)));
    float4 col2 = u_tex.sample(u_texSmplr, fast::clamp(in.v_uv - float2(_111.u_misreg * 0.699999988079071044921875, _111.u_misreg), float2(0.0), float2(1.0)));
    float lum1 = dot(col1.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float lum2 = dot(col2.xyz, float3(0.2989999949932098388671875, 0.58700001239776611328125, 0.114000000059604644775390625));
    float scale = (fast::min(_111.u_tex_w, _111.u_tex_h) / _111.u_dot_size) * 0.014999999664723873138427734375;
    float2 param = in.v_uv;
    float param_1 = scale;
    float param_2 = 0.785000026226043701171875;
    float param_3 = 1.0 - lum1;
    float dot1 = halftone(param, param_1, param_2, param_3);
    float2 param_4 = in.v_uv;
    float param_5 = scale;
    float param_6 = 0.3499999940395355224609375;
    float param_7 = 1.0 - lum2;
    float dot2 = halftone(param_4, param_5, param_6, param_7);
    float3 paper_col = float3(_111.u_paper, _111.u_paper * 0.959999978542327880859375, _111.u_paper * 0.87999999523162841796875);
    float param_8 = _111.u_hue1;
    float3 ink1 = hue2rgb(param_8);
    float param_9 = _111.u_hue2;
    float3 ink2 = hue2rgb(param_9);
    float3 result = paper_col;
    result = mix(result, ink1 * 0.85000002384185791015625, float3(dot1 * 0.800000011920928955078125));
    result = mix(result, ink2 * 0.800000011920928955078125, float3(dot2 * 0.699999988079071044921875));
    float overlap = dot1 * dot2;
    result = mix(result, ink1 * ink2, float3(overlap * 0.60000002384185791015625));
    out.frag = float4(fast::clamp(result, float3(0.0), float3(1.0)), col1.w);
    return out;
}

