"""
Claude Inspector - App Icon v4
크림 배경 + 선명한 Claude 아스테리스크 + 깔끔한 돋보기 링
"""
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
CX = CY = SIZE // 2

# 팔레트
BG_CTR  = (255, 250, 242)   # 따뜻한 크림
BG_EDG  = (238, 220, 195)   # 베이지
CLAUDE  = (210, 105, 72)    # Claude 시그니처 #D26948
CL_LT   = (235, 145, 105)   # 하이라이트
CL_DK   = (155, 65, 38)     # 섀도
RING    = (175, 80, 45)     # 돋보기 링
RING_LT = (220, 130, 90)    # 링 하이라이트
WHITE   = (255, 255, 255)

def squircle_mask(size, n=5.0):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = size / 2
    pts = []
    for i in range(4001):
        a = 2 * math.pi * i / 4000
        ca, sa = math.cos(a), math.sin(a)
        x = r * math.copysign(abs(ca)**(2/n), ca) + r
        y = r * math.copysign(abs(sa)**(2/n), sa) + r
        pts.append((x, y))
    d.polygon(pts, fill=255)
    return m

def radial_bg(size, c0, c1):
    img = Image.new("RGBA", (size, size), 0)
    d = ImageDraw.Draw(img)
    cx = cy = size / 2
    mr = math.sqrt(cx**2 + cy**2)
    for i in range(320, -1, -1):
        t = i / 320
        r = int(c0[0]*(1-t)+c1[0]*t)
        g = int(c0[1]*(1-t)+c1[1]*t)
        b = int(c0[2]*(1-t)+c1[2]*t)
        rr = mr * i / 320
        d.ellipse([cx-rr, cy-rr, cx+rr, cy+rr], fill=(r,g,b,255))
    return img

def pill(draw, cx, cy, length, width, angle_deg, fill):
    """회전된 둥근 직사각형(pill) 폴리곤으로 그리기"""
    a = math.radians(angle_deg)
    # 4 corner + arc approximation via polygon
    pts = []
    # pill = rounded rect: 양 끝 반원 + 사각형
    steps = 48
    for s in range(steps):
        t = 2 * math.pi * s / steps
        lx = length * math.cos(t)
        ly = width  * math.sin(t)
        # superellipse로 pill 모양
        n = 6.0
        lx2 = length * math.copysign(abs(math.cos(t))**(2/n), math.cos(t))
        ly2 = width  * math.copysign(abs(math.sin(t))**(2/n), math.sin(t))
        rx = lx2 * math.cos(a) - ly2 * math.sin(a)
        ry = lx2 * math.sin(a) + ly2 * math.cos(a)
        pts.append((cx + rx, cy + ry))
    draw.polygon(pts, fill=fill)

def draw_claude_mark(canvas, cx, cy, r):
    """
    Claude 로고: 3개 pill을 0°/60°/120°로 회전하여 겹침
    각 pill: 길이 r, 폭 r*0.25
    """
    L = int(r * 0.95)
    W = int(r * 0.235)

    # 1) 그림자 레이어
    sh = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    sd = ImageDraw.Draw(sh)
    for angle in [0, 60, 120]:
        pill(sd, cx+3, cy+5, L, W, angle, (*CL_DK, 120))
    sh = sh.filter(ImageFilter.GaussianBlur(8))
    canvas.alpha_composite(sh)

    # 2) 메인 pill 3개 (어두운 베이스)
    base = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    bd   = ImageDraw.Draw(base)
    for angle in [0, 60, 120]:
        pill(bd, cx, cy, L, W, angle, (*CL_DK, 255))
    canvas.alpha_composite(base)

    # 3) 밝은 오렌지 (살짝 작은 pill)
    mid = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    md  = ImageDraw.Draw(mid)
    for angle in [0, 60, 120]:
        pill(md, cx, cy, int(L*0.93), int(W*0.88), angle, (*CLAUDE, 255))
    canvas.alpha_composite(mid)

    # 4) 상단 하이라이트 (더 작고 밝은 pill)
    hi = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    hd = ImageDraw.Draw(hi)
    for angle in [0, 60, 120]:
        # 오프셋: 각 pill의 "위쪽" 방향으로 살짝 이동
        off_a = math.radians(angle + 90)
        ox = int(W * 0.25 * math.cos(off_a))
        oy = int(W * 0.25 * math.sin(off_a))
        pill(hd, cx+ox, cy+oy, int(L*0.82), int(W*0.45), angle, (*CL_LT, 200))
    hi = hi.filter(ImageFilter.GaussianBlur(2))
    canvas.alpha_composite(hi)

def draw_ring(canvas, cx, cy, r):
    """얇고 선명한 돋보기 링"""
    ring_r = int(r * 1.38)
    rw = 26

    L = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(L)

    # 외곽 그림자
    d.ellipse([cx-ring_r-2, cy-ring_r+4, cx+ring_r-2, cy+ring_r+4],
              outline=(*CL_DK, 100), width=rw+6)

    # 메인 링 (두 레이어: 어두운 + 밝은)
    d.ellipse([cx-ring_r, cy-ring_r, cx+ring_r, cy+ring_r],
              outline=(*CL_DK, 255), width=rw)
    d.ellipse([cx-ring_r, cy-ring_r, cx+ring_r, cy+ring_r],
              outline=(*RING, 240), width=rw-6)

    # 상단 좌 하이라이트 아크
    ap = rw // 2
    d.arc([cx-ring_r+ap, cy-ring_r+ap, cx+ring_r-ap, cy+ring_r-ap],
          start=205, end=305, fill=(*RING_LT, 220), width=rw//2)

    L = L.filter(ImageFilter.GaussianBlur(1))
    canvas.alpha_composite(L)

    draw_handle(canvas, cx, cy, ring_r, rw)

def draw_handle(canvas, cx, cy, ring_r, rw):
    ang = math.radians(132)
    sx = cx + ring_r * math.cos(ang)
    sy = cy + ring_r * math.sin(ang)
    ln = int(ring_r * 0.50)
    ex = sx + ln * math.cos(ang)
    ey = sy + ln * math.sin(ang)
    hw = rw + 4

    L = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    d = ImageDraw.Draw(L)

    # 그림자
    d.line([(sx+4, sy+6), (ex+4, ey+6)], fill=(*CL_DK, 90), width=hw+6)
    # 베이스
    d.line([(sx, sy), (ex, ey)], fill=(*CL_DK, 255), width=hw)
    # 밝은 면
    d.line([(sx, sy), (ex, ey)], fill=(*RING, 240), width=hw-8)
    # 하이라이트
    perp = ang - math.pi/2
    ox = (hw//3)*math.cos(perp)
    oy = (hw//3)*math.sin(perp)
    d.line([(sx+ox, sy+oy), (ex+ox*0.6, ey+oy*0.6)],
           fill=(*RING_LT, 130), width=4)

    L = L.filter(ImageFilter.GaussianBlur(1))
    canvas.alpha_composite(L)

def main():
    bg = radial_bg(SIZE, BG_CTR, BG_EDG)

    # 중심 미묘한 따뜻한 글로우
    glow = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    gd = ImageDraw.Draw(glow)
    for i in range(6, 0, -1):
        t = i / 6
        gr = int(SIZE * 0.32 * t)
        alpha = int(18 * (1-t))
        gd.ellipse([CX-gr, CY-gr, CX+gr, CY+gr], fill=(*CLAUDE, alpha))
    glow = glow.filter(ImageFilter.GaussianBlur(50))
    bg.alpha_composite(glow)

    mark_r = int(SIZE * 0.245)
    draw_claude_mark(bg, CX, CY, mark_r)
    draw_ring(bg, CX, CY, mark_r)

    mask = squircle_mask(SIZE)
    result = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    result.paste(bg, mask=mask)
    out = "/Users/ram/programming/vibecoding/claudeInspector/assets/icon.png"
    result.save(out, "PNG")
    print(f"Saved: {out}")

if __name__ == "__main__":
    main()
