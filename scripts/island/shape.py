import math
# 岛的轮廓：一圈控制点（格子坐标），闭合 Catmull-Rom 曲线，点在曲线里面就是陆地
CTRL = [(13,1.6),(17,2.4),(20,4.6),(21.2,7.6),(24,9.8),(26.6,13),(27,17),(25.6,20.2),
        (23.2,21.4),(22.4,24),(24.6,26.6),(25.8,30.4),(24,33.6),(20,35.6),(15,36.6),(10,36.2),
        (6,34.2),(3.8,31),(2.4,27),(3.6,23.6),(1.8,20),(1.4,16),(3,12.4),(4.6,8.8),(6.2,5.4),(9,3)]
def spline(pts, n=12):
    out = []
    m = len(pts)
    for i in range(m):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % m], pts[(i + 2) % m]
        for s in range(n):
            t = s / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in range(2)))
    return out
POLY = spline(CTRL)
def inside(px, py, poly=POLY):
    c = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]; xj, yj = poly[j]
        if (yi > py) != (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi: c = not c
        j = i
    return c
def land_at(x, y):
    px, py = x + 0.5, y + 0.5
    if math.hypot(px - 26.0, py - 4.6) < 2.6: return True     # 东北的小岛
    return inside(px, py)
if __name__ == "__main__":
    print('   '+''.join(str(i%10) for i in range(30)))
    for y in range(40): print('%2d '%y+''.join('.' if land_at(x,y) else '~' for x in range(30)))
