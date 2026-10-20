"""Icône plein cadre à partir du blason d'origine.

On garde le dessin d'origine (banderole, « 2020 », bandes, ballon) et on
enlève seulement la bordure du blason : le fond bleu et les bandes sont
prolongés jusqu'aux bords du carré. La croix d'origine (8 pommettes) est
effacée pour être remplacée par une vraie croix occitane (12 pommettes),
dessinée à part dans le même style.

Usage : python3 compose.py logo.webp sortie_dir
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

src = Path(sys.argv[1])
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)

O = Image.open(src).convert("RGBA")
W, H = O.size
rgba = np.asarray(O).astype(np.float32)
rgb = rgba[..., :3]
alpha = rgba[..., 3]

r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
is_gold = (r > 180) & (b < 120) & (g > 140)
is_blue = (b > 120) & (r < 60) & (g < 80)
is_field = is_gold | is_blue
is_white = rgb.min(-1) > 170
is_navy = (rgb.max(-1) < 75) & (alpha > 200)

# --- 1. intérieur du blason : forme opaque rognée de l'épaisseur de la bordure
BORDER = 26
opaque = Image.fromarray(((alpha > 200) * 255).astype(np.uint8))
interior_img = opaque
for _ in range(BORDER):
    interior_img = interior_img.filter(ImageFilter.MinFilter(3))
interior = np.asarray(interior_img) > 0

# --- 2. banderole : rangées occupées par la banderole sur les bords (là où passe la bordure)
ribbon_side = np.zeros((H, W), bool)
Y0, Y1 = 150, 400


def column_span(x):
    col_a = alpha[Y0:Y1, x]
    if x <= 44 or x >= 635:
        ys = np.nonzero(col_a > 0)[0]
        return (Y0 + ys[0], Y0 + ys[-1]) if len(ys) else None
    col_navy = is_navy[Y0:Y1, x]
    col_white = is_white[Y0:Y1, x]
    ys = np.nonzero(col_navy)[0]
    if not len(ys):
        return None
    top = Y0 + ys[0]
    # dernière ligne bleu nuit suivie de la bordure blanche jusqu'en bas de la zone
    bottom = None
    for i in range(len(col_navy) - 1, -1, -1):
        if col_navy[i] and col_white[i + 3 : i + 30].all():
            bottom = Y0 + i
            break
    return (top, bottom) if bottom else None


spans = {}
for x in list(range(0, 45)) + list(range(62, 72)) + list(range(608, 617)) + list(range(635, W)):
    s = column_span(x)
    if s:
        spans[x] = s
# près du bord intérieur de la bordure, la règle ne marche plus : on prolonge la dernière colonne mesurée
for x in range(72, 80):
    spans[x] = spans[71]
for x in range(600, 608):
    spans[x] = spans[608]
# colonnes du bord antialiasé et du filet bleu nuit de la bordure (et colonnes sans mesure) : interpolées
for lo_zone, hi_zone in ((0, 80), (600, W)):
    valid = sorted(x for x in spans if lo_zone <= x < hi_zone)
    for x in range(lo_zone, hi_zone):
        if x in spans or x < valid[0] or x > valid[-1]:
            continue
        lo = max(v for v in valid if v < x)
        hi = min(v for v in valid if v > x)
        t = (x - lo) / (hi - lo)
        spans[x] = tuple(round(spans[lo][k] * (1 - t) + spans[hi][k] * t) for k in range(2))
for x, (t, bt) in spans.items():
    ribbon_side[t : bt + 1, x] = True
ribbon_side &= alpha > 0

# --- 3. ballon : disque mesuré sur l'auréole blanche
BX, BY, BR = 339.5, 539.9, 177.6
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
ball_soft = np.clip(BR + 0.5 - np.hypot(xx - BX, yy - BY), 0, 1)

# --- 4. bande supérieure (au-dessus de la banderole) : bord haut de la banderole par colonne
ribbon_top = np.full(W, 400)
for x in range(W):
    col = is_navy[120:330, x] & ~is_field[120:330, x]
    # on remonte depuis l'intérieur de la banderole jusqu'au premier pixel de champ bleu
    mid = 250
    y = mid
    while y > 120 and not is_field[y, x]:
        y -= 1
    ribbon_top[x] = y + 1
top_field = yy < ribbon_top[None, :]

print("bord haut banderole", ribbon_top[[80, 150, 250, 340, 430, 530, 600]])
print("colonnes", {x: spans.get(x) for x in list(range(38, 82, 3)) + list(range(598, 642, 3))})

# --- 5. modèle du fond (pour tout ce qui n'est pas repris du dessin d'origine)
def clean(mask, k=13):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(k))
    return np.asarray(im) > 0


clean_blue = clean(is_blue) & interior
clean_field = clean(is_field, 7) & interior

# champ bleu du haut : surface lisse (polynôme de degré 2) ajustée sur le bleu « propre »
sel = clean_blue & top_field & (yy > 25)
X, Y = xx[sel] / W, yy[sel] / H
A = np.c_[np.ones_like(X), X, Y, X * X, X * Y, Y * Y]
coef = [np.linalg.lstsq(A, rgb[..., c][sel], rcond=None)[0] for c in range(3)]


def top_model(x, y):
    x = np.clip(x, 80, 600) / W
    y = np.clip(y, 25, None) / H
    A = np.stack([np.ones_like(x), x, y, x * x, x * y, y * y], -1)
    return np.stack([A @ cf for cf in coef], -1)


# bandes du bas : une couleur par colonne + pente verticale pour le bleu
ribbon_bottom = np.zeros(W, int)
for x in range(W):
    ys = np.nonzero(is_navy[150:400, x])[0]
    ribbon_bottom[x] = 150 + ys[-1] if len(ys) else 330
far_ball = np.hypot(xx - BX, yy - BY) > BR + 4
lower_ok = clean_field & far_ball & (yy > ribbon_bottom[None, :] + 14) & (yy < 640)
col_color = np.zeros((W, 3))
col_has = np.zeros(W, bool)
for x in range(78, 603):
    ys = np.nonzero(lower_ok[:, x])[0]
    if len(ys) >= 4:
        col_color[x] = np.median(rgb[ys, x], axis=0)
        col_has[x] = True
known = np.nonzero(col_has)[0]
for x in range(W):
    if not col_has[x]:
        col_color[x] = col_color[known[np.argmin(abs(known - min(max(x, 85), 595)))]]
# assombrissement vertical du bleu, mesuré sur les bandes bleues des bords
edge = lower_ok & is_blue & ((xx < 130) | (xx > 548))
ys_e, vals = yy[edge], rgb[edge]
slope = np.array([np.polyfit(ys_e, vals[:, c], 1)[0] for c in range(3)])
ref_y = np.array([np.median(yy[lower_ok[:, x], x]) if col_has[x] else 450 for x in range(W)])
blue_col = col_color[:, 2] > 120


def lower_model(x, y):
    xi = np.clip(x.astype(int), 0, W - 1)
    base = col_color[xi]
    s = np.where(blue_col[xi][..., None], slope[None, :], 0)
    return base + s * (y - ref_y[xi])[..., None]


print("pente bleu par pixel", np.round(slope, 4))
np.save(out / "debug_cols.npy", col_color)

# --- 6. assemblage
import json
import subprocess

params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
CX, CY, CD, CROT = params.get("cross", [472, 92, 108, -12])
here = Path(__file__).parent
SC = 3  # rendu de la croix en haute définition puis réduit
svg = subprocess.run(["node", str(here / "cross.js"), str(CX * SC), str(CY * SC), str(CD * SC), str(CROT), str(W * SC), str(H * SC)], capture_output=True, text=True, check=True).stdout
(out / "cross.svg").write_text(svg)
subprocess.run(["node", str(here / "render.js"), str(out / "cross.svg"), str(out / "cross_hd.png"), str(W * SC), str(H * SC)], check=True)
cross = np.asarray(Image.open(out / "cross_hd.png").convert("RGBA").resize((W, H), Image.LANCZOS)).astype(np.float32) / 255

rt = ribbon_top.copy()
# sur les côtés, le champ du haut descend jusqu'au bord haut de la banderole (ou de son pan replié)
sx = sorted(spans)
for x in list(range(0, 80)) + list(range(601, W)):
    nearest = min(sx, key=lambda v: abs(v - x))
    rt[x] = spans[nearest][0]
top_field = yy < rt[None, :]

model = np.where(top_field[..., None], top_model(xx, yy), lower_model(xx, yy))
# champ du haut : fond lisse + nouvelle croix (devant le fond, derrière la banderole)
ca = cross[..., 3:4] * top_field[..., None]
model = model * (1 - ca) + cross[..., :3] * 255 * ca

# ombre du ballon sur la bande or (à gauche) : dans l'original elle s'effile vers le bas mais
# la bordure la coupait net ; on la prolonge jusqu'à ce qu'elle s'efface.
theta = np.degrees(np.arctan2(-(yy - BY), xx - BX)) % 360
dist = np.hypot(xx - BX, yy - BY)
width = np.clip(4.5 * (216 - theta) / 16, 0, 4.5) * (theta >= 198)
interior_soft = np.asarray(Image.fromarray((interior * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 255
keep = np.maximum.reduce([interior_soft * (~top_field), ribbon_side.astype(np.float32), ball_soft])
gold_model = (model[..., 0] > 180) & (model[..., 2] < 120)
crescent = np.clip(BR + width - dist + 0.5, 0, 1) * (dist > BR - 1) * gold_model
shade = np.array([178, 128, 35], np.float32)
model = model * (1 - crescent[..., None]) + shade * crescent[..., None]
comp = model * (1 - keep[..., None]) + rgb * keep[..., None]
comp = np.clip(comp, 0, 255).astype(np.uint8)
full = Image.fromarray(comp, "RGB")
full.save(out / "full_native.png")

X0, Y0c, L = params.get("crop", [20, 20, 640])
crop = full.crop((X0, Y0c, X0 + L, Y0c + L))
crop.save(out / "icon_native.png")
print("ok", crop.size)
