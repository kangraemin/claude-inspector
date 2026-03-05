"""
Claude Inspector - 아이콘 6종 변형 생성
베이지 배경 + 오렌지 돋보기 심플 변형들
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 512
CX = CY = SIZE // 2

BG       = (248, 240, 225)   # 따뜻한 베이지
BG2      = (242, 230, 210)   # 진한 베이지
ORANGE   = (213, 101, 61)    # Claude 오렌지
OG_LT    = (238, 145, 100)   # 밝은 오렌지
OG_DK    = (158, 65, 28)     # 어두운 오렌지
WHITE    = (255, 255, 255)

def squircle(size, n=5.0):
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = size / 2
    pts = []
    for i in range(3001):
        a = 2*math.pi*i/3000
        ca, sa = math.cos(a), math.sin(a)
        x = r*math.copysign(abs(ca)**(2/n),ca)+r
        y = r*math.copysign(abs(sa)**(2/n),sa)+r
        pts.append((x,y))
    d.polygon(pts, fill=255)
    return m

def base_bg(color=BG):
    img = Image.new("RGBA", (SIZE, SIZE), (*color, 255))
    return img

def apply_mask(img):
    mask = squircle(SIZE)
    out = Image.new("RGBA", (SIZE, SIZE), (0,0,0,0))
    out.paste(img, mask=mask)
    return out

# ──────────────────────────────────────────────
# V1: 굵은 채움 돋보기 (클래식 플랫)
# ──────────────────────────────────────────────
def v1():
    img = base_bg()
    d = ImageDraw.Draw(img)
    cx, cy = CX, CY - 20
    r = 130
    hw = 34

    # 렌즈 채움
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*ORANGE, 255))
    # 렌즈 홀 (베이지)
    hr = r - hw
    d.ellipse([cx-hr, cy-hr, cx+hr, cy+hr], fill=(*BG, 255))
    # 하이라이트 아크
    d.arc([cx-hr+8, cy-hr+8, cx+hr-8, cy+hr-8],
          start=210, end=310, fill=(*OG_LT, 180), width=8)
    # 핸들
    ang = math.radians(135)
    sx = cx + r*math.cos(ang)
    sy = cy + r*math.sin(ang)
    ex = sx + 110*math.cos(ang)
    ey = sy + 110*math.sin(ang)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=hw-4)
    d.line([(sx,sy),(ex,ey)], fill=(*OG_LT,120), width=8)

    return apply_mask(img)

# ──────────────────────────────────────────────
# V2: 라인아트 (얇은 테두리만)
# ──────────────────────────────────────────────
def v2():
    img = base_bg()
    d = ImageDraw.Draw(img)
    cx, cy = CX, CY - 20
    r = 140
    lw = 18

    d.ellipse([cx-r, cy-r, cx+r, cy+r],
              outline=(*ORANGE,255), width=lw)
    # 십자선
    ir = r - lw - 8
    d.line([(cx-ir, cy),(cx+ir, cy)], fill=(*ORANGE,100), width=3)
    d.line([(cx, cy-ir),(cx, cy+ir)], fill=(*ORANGE,100), width=3)
    # 중심 점
    d.ellipse([cx-10,cy-10,cx+10,cy+10], fill=(*ORANGE,220))
    # 핸들
    ang = math.radians(135)
    sx = cx + r*math.cos(ang)
    sy = cy + r*math.sin(ang)
    ex = sx + 100*math.cos(ang)
    ey = sy + 100*math.sin(ang)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=lw)

    return apply_mask(img)

# ──────────────────────────────────────────────
# V3: 오렌지 꽉 채운 원 + 흰 심볼 (볼드 미니멀)
# ──────────────────────────────────────────────
def v3():
    img = base_bg(BG2)
    d = ImageDraw.Draw(img)
    cx, cy = CX-8, CY-8
    r = 155

    # 큰 오렌지 원
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*ORANGE,255))
    # 안에 흰 돋보기 홀
    hr = r - 44
    d.ellipse([cx-hr, cy-hr, cx+hr, cy+hr], fill=(*WHITE,230))
    # 베이지 내부
    ir = hr - 10
    d.ellipse([cx-ir, cy-ir, cx+ir, cy+ir], fill=(*BG2,255))

    # 핸들 (오렌지 원에서 이어지는 두꺼운 바)
    ang = math.radians(130)
    sx = cx + r*math.cos(ang)
    sy = cy + r*math.sin(ang)
    ex = sx + 90*math.cos(ang)
    ey = sy + 90*math.sin(ang)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=48)

    # 하이라이트
    d.arc([cx-r+15, cy-r+15, cx+r-15, cy+r-15],
          start=200, end=290, fill=(*OG_LT,160), width=14)

    return apply_mask(img)

# ──────────────────────────────────────────────
# V4: 듀얼 링 (동심원 두 개 + 핸들)
# ──────────────────────────────────────────────
def v4():
    img = base_bg()
    d = ImageDraw.Draw(img)
    cx, cy = CX, CY-15
    r1, r2 = 150, 100
    lw = 16

    d.ellipse([cx-r1, cy-r1, cx+r1, cy+r1], outline=(*ORANGE,255), width=lw)
    d.ellipse([cx-r2, cy-r2, cx+r2, cy+r2], outline=(*ORANGE,180), width=lw//2)
    # 중심 점
    d.ellipse([cx-14,cy-14,cx+14,cy+14], fill=(*ORANGE,255))
    # 십자 (안쪽 링 안에)
    ir = r2 - 16
    d.line([(cx-ir,cy),(cx+ir,cy)], fill=(*ORANGE,130), width=3)
    d.line([(cx,cy-ir),(cx,cy+ir)], fill=(*ORANGE,130), width=3)
    # 핸들
    ang = math.radians(132)
    sx = cx + r1*math.cos(ang)
    sy = cy + r1*math.sin(ang)
    ex = sx + 110*math.cos(ang)
    ey = sy + 110*math.sin(ang)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=lw+4)

    return apply_mask(img)

# ──────────────────────────────────────────────
# V5: 그림자 있는 입체감 돋보기
# ──────────────────────────────────────────────
def v5():
    img = base_bg()
    cx, cy = CX-5, CY-25
    r = 135
    hw = 36

    # 그림자
    sh = Image.new("RGBA",(SIZE,SIZE),(0,0,0,0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse([cx-r+8, cy-r+12, cx+r+8, cy+r+12], fill=(*OG_DK,80))
    sh = sh.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(sh)

    d = ImageDraw.Draw(img)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*ORANGE,255))
    hr = r - hw
    d.ellipse([cx-hr, cy-hr, cx+hr, cy+hr], fill=(*BG,255))

    # 내부 미묘한 그라데이션 느낌
    for i in range(3):
        rr = hr - i*12
        alpha = 20+i*15
        d.ellipse([cx-rr+20, cy-rr+5, cx+rr-20, cy+rr-5],
                  outline=(*OG_LT, alpha), width=4)

    d.arc([cx-r+6, cy-r+6, cx+r-6, cy+r-6],
          start=205, end=305, fill=(*OG_LT,200), width=hw//2)

    # 핸들 그림자
    ang = math.radians(135)
    sx = cx + r*math.cos(ang)
    sy = cy + r*math.sin(ang)
    ex = sx + 115*math.cos(ang)
    ey = sy + 115*math.sin(ang)
    d.line([(sx+6,sy+8),(ex+6,ey+8)], fill=(*OG_DK,60), width=hw+4)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=hw)
    d.line([(sx,sy),(ex,ey)], fill=(*OG_LT,100), width=8)

    return apply_mask(img)

# ──────────────────────────────────────────────
# V6: 돋보기 안에 'CI' 레터마크
# ──────────────────────────────────────────────
def v6():
    img = base_bg(BG)
    d = ImageDraw.Draw(img)
    cx, cy = CX+5, CY-20
    r = 145
    lw = 22

    # 렌즈 링 (단색, 하이라이트 없음)
    d.ellipse([cx-r, cy-r, cx+r, cy+r], fill=(*ORANGE,255))
    hr = r - lw
    d.ellipse([cx-hr, cy-hr, cx+hr, cy+hr], fill=(*BG,255))

    # 핸들 (단색)
    ang = math.radians(135)
    sx = cx + r*math.cos(ang)
    sy = cy + r*math.sin(ang)
    ex = sx + 100*math.cos(ang)
    ey = sy + 100*math.sin(ang)
    d.line([(sx,sy),(ex,ey)], fill=(*ORANGE,255), width=lw+2)

    return apply_mask(img)


# ── 생성 ──────────────────────────────────────
variants = [
    ("v1_classic_flat",  v1()),
    ("v2_lineart",       v2()),
    ("v3_bold_circle",   v3()),
    ("v4_dual_ring",     v4()),
    ("v5_shadow_depth",  v5()),
    ("v6_lettermark",    v6()),
]

base = "/Users/ram/programming/vibecoding/claudeInspector/assets"
for name, img in variants:
    path = f"{base}/icon_{name}.png"
    img.save(path, "PNG")
    print(f"Saved: icon_{name}.png")
