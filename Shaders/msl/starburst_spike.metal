#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

struct Params
{
    float u_tex_w;
    float u_tex_h;
    float u_threshold;
    float u_length;
    float u_rays;
};

struct fx_starburst_spike_out
{
    float4 frag [[color(0)]];
};

struct fx_starburst_spike_in
{
    float2 v_uv [[user(locn0)]];
};

fragment fx_starburst_spike_out fx_starburst_spike(fx_starburst_spike_in in [[stage_in]], constant Params& _25 [[buffer(0)]], texture2d<float> u_tex [[texture(0)]], sampler u_texSmplr [[sampler(0)]])
{
    fx_starburst_spike_out out = {};
    float4 col = u_tex.sample(u_texSmplr, in.v_uv);
    float2 ipx = float2(1.0 / _25.u_tex_w, 1.0 / _25.u_tex_h);
    int N = int(_25.u_rays);
    float3 burst = float3(0.0);
    for (int r = 0; r < N; r++)
    {
        float ang = (3.1415927410125732421875 * float(r)) / float(N);
        float2 dir = float2(cos(ang) * ipx.x, sin(ang) * ipx.y);
        for (int s = 1; s <= 40; s++)
        {
            float t = float(s) / 40.0;
            if (t > (_25.u_length * 4.0))
            {
                break;
            }
            float wt = (1.0 - t) * exp((-t) * 3.0);
            float2 uv_a = in.v_uv + (((dir * float(s)) * 28.0) * _25.u_length);
            float2 uv_b = in.v_uv - (((dir * float(s)) * 28.0) * _25.u_length);
            float3 ca = u_tex.sample(u_texSmplr, fast::clamp(uv_a, float2(0.0), float2(1.0))).xyz;
            float3 cb = u_tex.sample(u_texSmplr, fast::clamp(uv_b, float2(0.0), float2(1.0))).xyz;
            float ba = dot(ca, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
            float bb = dot(cb, float3(0.2125999927520751953125, 0.715200006961822509765625, 0.072200000286102294921875));
            burst += (((ca * step(_25.u_threshold, ba)) + (cb * step(_25.u_threshold, bb))) * wt);
        }
    }
    burst /= float3(float(N) * 2.5);
    out.frag = float4(fast::clamp(col.xyz + burst, float3(0.0), float3(1.0)), col.w);
    return out;
}

