"""Draws the Home Screen icon: a teal metronome line glyph on the dark charcoal of Joe's other app icons
(background #141518, stroke #6FB7A0, the camera and f icons' stroke weight). python scripts/make-icon.py"""
import math, os
from PIL import Image, ImageDraw

S = 4  # drawn at 4x, then scaled down for smooth edges
W = 1024 * S
BG, FG = (20, 21, 24), (111, 183, 160)
STROKE = 52 * S

img = Image.new("RGB", (W, W), BG)
d = ImageDraw.Draw(img)

def p(x, y): return (x * S, y * S)

def line(a, b):
    d.line([p(*a), p(*b)], fill=FG, width=STROKE)
    for c in (a, b):
        r = STROKE / 2
        d.ellipse([c[0] * S - r, c[1] * S - r, c[0] * S + r, c[1] * S + r], fill=FG)

# The body: a tall trapezoid with a flat top, outline only.
bl, br, tr, tl = (282, 790), (742, 790), (590, 236), (434, 236)
for a, b in [(bl, br), (br, tr), (tr, tl), (tl, bl)]:
    line(a, b)
# The face line across the lower body, where the pendulum's pivot sits.
line((330, 640), (694, 640))
# The pendulum, leaning right, from the pivot up past the body.
pivot = (512, 640)
ang = math.radians(24)
L = 470
tip = (pivot[0] + L * math.sin(ang), pivot[1] - L * math.cos(ang))
line(pivot, tip)
# The weight on the pendulum: a solid rounded block.
t = 0.62
wx, wy = pivot[0] + (tip[0] - pivot[0]) * t, pivot[1] + (tip[1] - pivot[1]) * t
blk = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bd = ImageDraw.Draw(blk)
bw, bh = 120 * S, 78 * S
bd.rounded_rectangle([wx * S - bw / 2, wy * S - bh / 2, wx * S + bw / 2, wy * S + bh / 2], radius=20 * S, fill=FG + (255,))
blk = blk.rotate(-math.degrees(ang), center=(wx * S, wy * S), resample=Image.BICUBIC)
img.paste(blk, (0, 0), blk)

out = img.resize((1024, 1024), Image.LANCZOS)
dest = os.path.join(os.path.dirname(__file__), "..", "ios", "Practice", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")
out.save(dest)
print("wrote", os.path.abspath(dest))
