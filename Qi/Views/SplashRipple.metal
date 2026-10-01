#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 开屏那扇窗（见 SplashView）。
//
// r 里每四个数是一圈涟漪：圆心 x、圆心 y、出生了几秒、多大力。
// 波前以固定速度往外走，越走越弱；经过的地方把画面推开一点（折射），波峰上加一点亮（反光）。
//
// ⚠️ 推开的距离要限住，取样点也要夹在画面里：
// 几圈叠在一起推得太远，会取到画面外面——那儿是空的，就露出一格一格的方块和白边。

static float2 rippleOffset(float2 pos, device const float *r, int count, thread float &shine) {
    float2 off = float2(0.0);
    shine = 0.0;
    for (int i = 0; i + 3 < count; i += 4) {
        float2 c = float2(r[i], r[i + 1]);
        float age = r[i + 2];
        float amp = r[i + 3];
        float2 v = pos - c;
        float d = length(v);
        float x = d - age * 240.0;
        float env = exp(-x * x / 2600.0) * exp(-age * 1.25) * amp;
        float2 dir = d > 0.001 ? v / d : float2(0.0);
        off += dir * sin(x * 0.11) * env * 12.0;
        shine += max(0.0, cos(x * 0.11)) * env;
    }
    float len = length(off);
    if (len > 30.0) { off *= 30.0 / len; }
    return off;
}

[[ stitchable ]] half4 qiRipple(float2 pos, SwiftUI::Layer layer, device const float *r, int count, float2 size) {
    float shine;
    float2 off = rippleOffset(pos, r, count, shine);
    float2 p = clamp(pos - off, float2(1.0), size - 1.0);
    half4 col = layer.sample(p);
    col.rgb += half3(min(shine, 1.5) * 0.07);
    return col;
}

// MARK: 彩绘玻璃

static float2 h2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

static float fmod2(float x, float y) { return x - y * floor(x / y); }

// 一块玻璃的颜色：浅紫、藕粉、零星酒红、珍珠白、雾蓝、香槟金
static float3 pane(float k, float yy) {
    float j = fract(k * 6.0 + yy * 1.3);
    if (j < 0.20) return float3(0.76, 0.72, 0.91);
    if (j < 0.38) return float3(0.93, 0.72, 0.78);
    if (j < 0.45) return float3(0.64, 0.22, 0.32);
    if (j < 0.72) return float3(0.97, 0.95, 0.91);
    if (j < 0.85) return float3(0.56, 0.62, 0.85);
    return float3(0.96, 0.87, 0.66);
}

// 左右对称的一扇窗：上半一朵玫瑰花窗（一圈圈花瓣格），其余是大小不一的碎玻璃，金色铅条隔开
static float3 stained(float2 p, float2 s, float time) {
    float2 ctr = float2(s.x * 0.5, s.x * 0.5);
    float R = s.x * 0.24;
    float dc = length(p - ctr);
    float3 col;
    float lead;
    if (dc < R) {
        float ang = atan2(p.y - ctr.y, abs(p.x - ctr.x));
        float seg = 3.14159 / 6.0;
        float ring = floor(dc / (R / 3.0));
        float sid = floor(ang / seg);
        float fa = fract(ang / seg), fr = fract(dc / (R / 3.0));
        lead = min(min(fa, 1.0 - fa) * dc * seg, min(fr, 1.0 - fr) * R / 3.0);
        lead = min(lead, R - dc);
        if (ring < 1.0) col = float3(0.97, 0.88, 0.66);
        else if (ring < 2.0) col = fmod2(sid, 3.0) < 1.0 ? float3(0.66, 0.22, 0.33) : float3(0.94, 0.74, 0.80);
        else col = fmod2(sid, 2.0) < 1.0 ? float3(0.58, 0.64, 0.88) : float3(0.80, 0.76, 0.93);
        col *= 1.08 - fr * 0.16;
    } else {
        float2 q = float2(abs(p.x - s.x * 0.5), p.y) / 22.0;
        float2 i = floor(q), f = fract(q);
        float d1 = 9.0, d2 = 9.0;
        float2 id = float2(0.0);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                float2 g = float2(float(x), float(y));
                float2 o = h2(i + g) * 0.8 + 0.1;
                float2 rr = g + o - f;
                float d = dot(rr, rr);
                if (d < d1) { d2 = d1; d1 = d; id = i + g; }
                else if (d < d2) { d2 = d; }
            }
        }
        lead = (sqrt(d2) - sqrt(d1)) * 11.0;
        col = pane(h2(id).x, p.y / s.y) * mix(1.1, 0.86, clamp(sqrt(d1) / 0.8, 0.0, 1.0));
        lead = min(lead, dc - R);
    }
    // 竖中梃：花窗以下才有
    if (p.y > s.x * 0.5 + s.x * 0.24) { lead = min(lead, abs(p.x - s.x * 0.5)); }
    col *= 0.92 + h2(floor(p / 2.0)).x * 0.06;
    // 光从上面透进来，慢慢左右移
    float2 lc = float2(s.x * (0.5 + 0.18 * sin(time * 0.2)), s.y * 0.12);
    float glow = 0.86 + 0.32 * exp(-pow(length(p - lc) / (s.x * 0.9), 2.0));
    col *= glow;
    float3 leadCol = float3(0.48, 0.38, 0.22);
    return mix(leadCol, col, smoothstep(0.3, 1.1, lead));
}

[[ stitchable ]] half4 qiStained(float2 pos, half4 color, device const float *r, int count, float2 size, float time) {
    float shine;
    float2 off = rippleOffset(pos, r, count, shine);
    float3 c = stained(clamp(pos - off, float2(1.0), size - 1.0), size, time) + min(shine, 1.5) * 0.12;
    return half4(half3(c) * color.a, color.a);
}
