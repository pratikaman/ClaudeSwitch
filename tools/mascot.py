import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREVIEW = os.path.join(ROOT, "build", "preview")   # gitignored

# ---- palette -------------------------------------------------------------
BODY  = (202, 124,  94)     # terracotta — the app's brand colour
SHADE = (168,  97,  71)     # bottom-edge shading
INK   = (14,   17,  22)     # near-black, the app background colour
LENS  = (243, 238, 231)     # cream glass
RIM   = (202, 124,  94)     # brand rim

W, H = 21, 19               # mascot grid

# ---- grid ----------------------------------------------------------------
# Built from rectangles rather than hand-typed rows — the ASCII version was
# too easy to get subtly wrong.
g = [[None] * W for _ in range(H)]

def rect(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            g[y][x] = ch

def ring(x0, y0, x1, y1, ch):
    rect(x0, y0, x1, y0, ch); rect(x0, y1, x1, y1, ch)
    rect(x0, y0, x0, y1, ch); rect(x1, y0, x1, y1, ch)

# body: inset crown, full torso, stubby arms, shaded lower lip
rect(5,  1, 15,  2, "B")
rect(3,  3, 17, 12, "B")
rect(1,  8,  2,  9, "B")
rect(18, 8, 19,  9, "B")
rect(3, 13, 17, 13, "S")

# three legs, evenly spaced, outer pair flush with the body edges
for lx in (3, 9, 15):
    rect(lx, 14, lx + 2, 16, "B")
    rect(lx, 17, lx + 2, 17, "S")

# glasses: two lenses, a bridge, and temples reaching the body edges
for fx in (4, 12):                       # frame left edges
    ring(fx, 4, fx + 4, 8, "K")          # 5x5 frame
    rect(fx + 1, 5, fx + 3, 7, "L")      # 3x3 glass
    rect(fx + 1, 6, fx + 3, 7, "K")      # pupil, cream glare left on top
rect(9, 6, 11, 6, "K")                   # bridge
rect(3, 6,  3, 6, "K")                   # left temple
rect(17, 6, 17, 6, "K")                  # right temple

COLORS = {"B": BODY, "S": SHADE, "K": INK, "L": LENS}


def mascot_layer(cell):
    img = Image.new("RGBA", (W * cell, H * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):
        for x in range(W):
            ch = g[y][x]
            if ch:
                d.rectangle([x * cell, y * cell, (x + 1) * cell - 1, (y + 1) * cell - 1],
                            fill=COLORS[ch])
    return img


def squircle(size, fill=(20, 23, 29, 255)):
    """macOS-style rounded tile, drawn 4x and downsampled for clean edges."""
    s = size * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle([0, 0, s - 1, s - 1],
                                          radius=int(s * 0.2237), fill=fill)
    return img.resize((size, size), Image.LANCZOS)


def icon(size):
    tile = squircle(size)

    rim = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inset = max(1, round(size * 0.012))
    ImageDraw.Draw(rim).rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=int(size * 0.2237), outline=RIM + (90,), width=max(1, round(size * 0.008)))
    tile = Image.alpha_composite(tile, rim)

    target_w = size * 0.68
    cell = max(1, round(target_w / W))
    art = mascot_layer(cell)
    art = art.crop(art.getbbox())
    if art.width > target_w:
        s = target_w / art.width
        art = art.resize((max(1, round(art.width * s)), max(1, round(art.height * s))),
                         Image.NEAREST)

    tile.alpha_composite(art, ((size - art.width) // 2,
                               (size - art.height) // 2 - round(size * 0.01)))
    return tile


out = os.path.join(ROOT, "Resources")
iconset = os.path.join(out, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
os.makedirs(PREVIEW, exist_ok=True)
for base in (16, 32, 128, 256, 512):
    icon(base).save(f"{iconset}/icon_{base}x{base}.png")
    icon(base * 2).save(f"{iconset}/icon_{base}x{base}@2x.png")

icon(512).save(f"{PREVIEW}/icon-preview.png")
m = mascot_layer(22); m.crop(m.getbbox()).save(f"{PREVIEW}/mascot.png")

# small-size legibility check
strip = Image.new("RGBA", (16 + 32 + 64 + 40, 64), (30, 30, 34, 255))
x = 8
for s in (16, 32, 64):
    strip.alpha_composite(icon(s), (x, (64 - s) // 2)); x += s + 12
strip.save(f"{PREVIEW}/icon-sizes.png")
print("ok")

# ---- in-app artwork ------------------------------------------------------

def trimmed(cell):
    m = mascot_layer(cell)
    return m.crop(m.getbbox())

def template(height):
    """Monochrome menu-bar glyph: body opaque, glasses punched out as holes.
    macOS tints template images to match the menu bar, so shape is all we get."""
    cell = max(1, round(height / H))
    img = Image.new("RGBA", (W * cell, H * cell), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):
        for x in range(W):
            if g[y][x] in ("B", "S"):        # body only; glasses stay transparent
                d.rectangle([x * cell, y * cell, (x + 1) * cell - 1, (y + 1) * cell - 1],
                            fill=(0, 0, 0, 255))
    return img.crop(img.getbbox())

res = os.path.join(ROOT, "Resources")
template(18).save(f"{res}/menubar.png")
template(36).save(f"{res}/menubar@2x.png")
trimmed(2).save(f"{res}/mascot.png")
trimmed(4).save(f"{res}/mascot@2x.png")

prev = Image.new("RGBA", (240, 60), (30, 30, 34, 255))
t = template(36)
prev.alpha_composite(Image.merge("RGBA", (*[Image.new("L", t.size, 235)] * 3, t.split()[3])), (14, 12))
prev.alpha_composite(trimmed(3), (90, 8))
prev.save(f"{PREVIEW}/inapp.png")
print("in-app art written")
