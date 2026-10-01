#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 开屏那片水面的涟漪（见 SplashView）。
//
// r 里每四个数是一圈：圆心 x、圆心 y、出生了几秒、多大力。
// 波前以固定速度往外走，越走越弱；经过的地方按波的斜率把底下的画面推开一点（折射），
// 波峰上加一点亮（反光）。
//
// ⚠️ 推开的距离要限住（不超过 maxSampleOffset），取样点也要夹在画面里：
// 几圈叠在一起推得太远，会取到画面外面——那儿是空的，就露出一格一格的方块和白边。
[[ stitchable ]] half4 qiRipple(float2 pos, SwiftUI::Layer layer, device const float *r, int count, float2 size) {
    float2 off = float2(0.0);
    float shine = 0.0;
    for (int i = 0; i + 3 < count; i += 4) {
        float2 c = float2(r[i], r[i + 1]);
        float age = r[i + 2];
        float amp = r[i + 3];
        float2 v = pos - c;
        float d = length(v);
        float x = d - age * 240.0;
        // 一圈波只有一段宽：前后各几十点，再往外就平了
        float env = exp(-x * x / 2600.0) * exp(-age * 1.25) * amp;
        float w = sin(x * 0.11) * env;
        float2 dir = d > 0.001 ? v / d : float2(0.0);
        off += dir * w * 12.0;
        shine += max(0.0, cos(x * 0.11)) * env;
    }
    float len = length(off);
    if (len > 30.0) { off *= 30.0 / len; }
    float2 p = clamp(pos - off, float2(1.0), size - 1.0);
    half4 col = layer.sample(p);
    col.rgb += half3(min(shine, 1.5) * 0.07);
    return col;
}
