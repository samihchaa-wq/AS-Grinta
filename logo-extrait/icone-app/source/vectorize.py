"""Version vectorielle (SVG) de l'icône.

- fond bleu, bandes et croix : dessinés directement en vectoriel (formes exactes) ;
- banderole, « 2020 » et ballon : dessin d'origine converti en formes vectorielles
  (vectorisation automatique, faite sur l'image agrandie pour lisser les contours).

Usage : python3 vectorize.py out_dir icone.svg
"""
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import vtracer
from PIL import Image, ImageFilter

out = Path(sys.argv[1])
dest = Path(sys.argv[2])
here = Path(__file__).parent
d = np.load(out / "vector_data.npz")
comp, base, top_field = d["comp"].astype(np.float32), d["base"], d["top_field"]
col_color, slope, ref_y = d["col_color"], d["slope"], d["ref_y"]
rt, ribbon_bottom, ribbon_side = d["rt"], d["ribbon_bottom"], d["ribbon_side"]
BX, BY, BR = d["ball"]
coef = d["coef"]
H, W = top_field.shape
X0, Y0, L = 20, 20, 640
CROSS = (472, 92, 108, -12)
UP = 4  # agrandissement avant vectorisation
import os
SHARP = int(os.environ.get("SHARP", "7"))
LAYER = int(os.environ.get("LAYER", "12"))
PREC = int(os.environ.get("PREC", "7"))
CORNER = int(os.environ.get("CORNER", "80"))
LENGTH = float(os.environ.get("LENGTH", "6"))
SPLICE = int(os.environ.get("SPLICE", "60"))
SPECKLE = int(os.environ.get("SPECKLE", "12"))
NCOL = int(os.environ.get("NCOL", "28"))
MODE = int(os.environ.get("MODE", "7"))

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)

# --- texte : vraies lettres vectorielles (police retrouvée et calée sur l'original, cf. textfit.py)
import json
text = json.loads((out / "text_fit.json").read_text())
TEXT_COLOR, YEAR_COLOR = "#02081E", "#030B2A"
mask_svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
            f'<path d="{text["ribbon"]["d"]}" fill="#000"/><path d="{text["year"]["d"]}" fill="#000"/></svg>')
(out / "text_mask.svg").write_text(mask_svg)
subprocess.run(["node", str(here / "render.js"), str(out / "text_mask.svg"), str(out / "text_mask.png"), str(W), str(H)], check=True)
tmask = np.asarray(Image.open(out / "text_mask.png").getchannel("A").filter(ImageFilter.MaxFilter(9))) > 0
year_zone = (yy > 300) & (yy < 362) & (xx > 270) & (xx < 410)
year_mask = tmask & year_zone
r_, g_, b_ = comp[..., 0], comp[..., 1], comp[..., 2]
field = ((r_ > 180) & (b_ < 120) & (g_ > 140)) | ((b_ > 120) & (r_ < 60) & (g_ < 80))
rb_true = ribbon_bottom.copy()
for x in range(80, 601):
    y = rt[x] + 12
    while y < H - 1 and not field[y, x]:
        y += 1
    rb_true[x] = min(y - 1, rt[x] + 130)
# les colonnes posées sur une jointure de bandes (pixels mélangés) faussent la mesure : médiane glissante
rb_true[80:601] = [int(np.median(rb_true[max(80, x - 6):min(601, x + 7)])) for x in range(80, 601)]
# zone claire entre les deux filets bleu nuit : on part des filets et on s'arrête au premier pixel clair
lumc = comp.mean(-1)
band_top = np.zeros(W, int)
band_bot = np.zeros(W, int)
for x in range(80, 601):
    y = rt[x]
    while y < rb_true[x] and lumc[y, x] < 150:
        y += 1
    band_top[x] = y + 1
    y = rb_true[x]
    while y > rt[x] and lumc[y, x] < 150:
        y -= 1
    band_bot[x] = y - 1
inner_band = (yy >= band_top[None, :]) & (yy <= band_bot[None, :]) & (xx > 85) & (xx < 595)
dark_in_band = np.asarray(Image.fromarray(((comp.mean(-1) < 200) & inner_band).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))) > 0
ribbon_text = ((tmask & ~year_zone) | dark_in_band) & inner_band
# (le lissage du fond de la banderole est fait plus bas, après effacement du texte)
# on efface le texte de la banderole : chaque colonne est recomblée entre le blanc au-dessus et au-dessous
comp = comp.copy()
for x in np.nonzero(ribbon_text.any(0))[0]:
    col = ribbon_text[:, x]
    ys = np.nonzero(col)[0]
    runs = np.split(ys, np.nonzero(np.diff(ys) > 1)[0] + 1)
    for run in runs:
        # bornes : premier pixel clair (fond de la banderole) au-dessus et au-dessous, sans toucher aux filets
        y0, y1 = run[0] - 1, run[-1] + 1
        while y0 > run[0] - 8 and comp[y0, x].mean() < 150:
            y0 -= 1
        while y1 < run[-1] + 8 and comp[y1, x].mean() < 150:
            y1 += 1
        top_c = comp[y0, x] if comp[y0, x].mean() >= 150 else comp[y1, x]
        bot_c = comp[y1, x] if comp[y1, x].mean() >= 150 else top_c
        for c in range(3):
            comp[run, x, c] = np.interp(run, [run[0] - 1, run[-1] + 1], [top_c[c], bot_c[c]])

# segments de bandes : famille (or / bleu) de chaque colonne, par vote sur les pixels de champ
# visibles de l'original (sous la banderole, hors ballon)
orig = comp
r_, g_, b_ = orig[..., 0], orig[..., 1], orig[..., 2]
gold_px = (r_ > 180) & (b_ < 120) & (g_ > 140)
blue_px = (b_ > 120) & (r_ < 60) & (g_ < 80)
zone = (yy > rb_true[None, :] + 4) & (yy < 600) & (np.hypot(xx - BX, yy - BY) > BR + 3)
votes_g = (gold_px & zone).sum(0)
votes_b = (blue_px & zone).sum(0)
is_blue_col = votes_b >= votes_g
is_blue_col[:85] = True
is_blue_col[596:] = True
gold_color = np.median(orig[gold_px & zone], axis=0)
# fond de référence fidèle aux bandes réelles (or uni / bleu dégradé), pour repérer ce qui dépasse du fond
blue_model = col_color[np.clip(xx.astype(int), 0, W - 1)] + slope[None, None, :] * (yy - ref_y[np.clip(xx.astype(int), 0, W - 1)])[..., None]
stripe_model = np.where(is_blue_col[np.clip(xx.astype(int), 0, W - 1)][..., None], blue_model, gold_color[None, None, :])
base = np.where(top_field[..., None], base, stripe_model)

# --- premier plan à vectoriser : banderole, texte, ballon (+ leurs ombres)
diff = np.abs(comp - base).max(-1) > 22
# ouverture morphologique : supprime les fines lignes (1 à 2 px) aux jointures des bandes
diff_img = Image.fromarray((diff * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))
diff = np.asarray(diff_img) > 0
ribbon = (yy >= rt[None, :] - 1) & (yy <= rb_true[None, :] + 2)
ribbon[:, :80] = False
ribbon[:, 601:] = False
ball = np.hypot(xx - BX, yy - BY) <= BR + 1
# autour de « 2020 » il n'y a que la bande or (vectorielle) : rien à vectoriser dans ce cadre
year_box = (yy >= 306) & (yy <= 358) & (xx >= 262) & (xx <= 418)
fg = ((diff & ~top_field & ~year_mask & ~year_box) | ball | ribbon | ribbon_side)
fg_img = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))
fg = np.asarray(fg_img) > 0
# on ne garde que la zone visible dans l'icône (avec une marge)
win = (xx >= X0 - 8) & (xx < X0 + L + 8) & (yy >= Y0 - 8) & (yy < Y0 + L + 8)
fg &= win

# fond de la banderole : on lisse les petites irrégularités de l'original (moyenne pondérée
# limitée à la zone claire), pour obtenir des dégradés propres plutôt que des taches
def smooth_in(mask, radius):
    m = Image.fromarray((mask * 255).astype(np.uint8))
    wsum = np.asarray(m.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255
    res = np.zeros_like(comp)
    for c in range(3):
        ch = Image.fromarray(np.clip(comp[..., c] * mask, 0, 255).astype(np.uint8))
        res[..., c] = np.asarray(ch.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / np.maximum(wsum, 1e-3)
    return res


light_band = inner_band & (comp.mean(-1) >= 150)
sm = smooth_in(light_band, 5)
comp = np.where(light_band[..., None], sm, comp)
rgba = np.dstack([np.clip(comp, 0, 255), fg * 255.0]).astype(np.uint8)
src = Image.fromarray(rgba, "RGBA")
big_rgb = src.convert("RGB").resize((W * UP, H * UP), Image.LANCZOS)
# l'agrandissement adoucit les bords ; un filtre médian les redresse avant la vectorisation,
# pour obtenir des contours nets plutôt qu'un dégradé flou en bandes
big_rgb = big_rgb.filter(ImageFilter.MedianFilter(int(SHARP))) if SHARP else big_rgb
# palette réduite + filtre « majoritaire » : les pixels de transition (anticrénelage) rejoignent
# la zone voisine, ce qui évite les fins liserés gris entre les couleurs
if NCOL:
    q = big_rgb.quantize(colors=NCOL, method=Image.Quantize.MEDIANCUT, kmeans=3, dither=Image.Dither.NONE)
    q = q.filter(ImageFilter.ModeFilter(MODE))
    big_rgb = q.convert("RGB")
big_a = src.getchannel("A").resize((W * UP, H * UP), Image.BILINEAR).point(lambda v: 255 if v >= 128 else 0)
big = big_rgb.convert("RGBA")
big.putalpha(big_a)
big.save(out / "fg_big.png")

vtracer.convert_image_to_svg_py(
    str(out / "fg_big.png"), str(out / "fg_traced.svg"),
    colormode="color", hierarchical="stacked", mode="spline",
    filter_speckle=SPECKLE, color_precision=PREC, layer_difference=LAYER,
    corner_threshold=CORNER, length_threshold=LENGTH, max_iterations=10,
    splice_threshold=SPLICE, path_precision=1,
)
traced = (out / "fg_traced.svg").read_text()
paths = "\n".join(re.findall(r"<path[^>]*/>", traced))

# --- fond : champ bleu du haut (dégradé vertical) + bandes
def top_color(y):
    x = 300 / W
    yv = max(y, 25) / H
    A = np.array([1, x, yv, x * x, x * yv, yv * yv])
    return [float(A @ c) for c in coef]


def hexc(c):
    return "#" + "".join(f"{int(round(min(255, max(0, v)))):02X}" for v in c)


defs = [f'<linearGradient id="top" x1="0" y1="{Y0}" x2="0" y2="260" gradientUnits="userSpaceOnUse">'
        f'<stop offset="0" stop-color="{hexc(top_color(Y0))}"/><stop offset="1" stop-color="{hexc(top_color(260))}"/></linearGradient>']
shapes = [f'<rect x="{X0 - 10}" y="{Y0 - 10}" width="{L + 20}" height="{260 - Y0 + 10}" fill="url(#top)"/>']


segs = []
start = 0
for x in range(1, W + 1):
    if x == W or is_blue_col[x] != is_blue_col[start]:
        segs.append((start, x, is_blue_col[start]))
        start = x
SY0, SY1 = 250, H
for i, (a, b, blue) in enumerate(segs):
    xa = a if a > 0 else X0 - 10
    xb = b if b < W else X0 + L + 10
    c = np.median(col_color[a:b], axis=0) if blue else gold_color
    if blue:
        ry = float(np.median(ref_y[a:b]))
        c0 = c + slope * (SY0 - ry)
        c1 = c + slope * (SY1 - ry)
        defs.append(f'<linearGradient id="s{i}" x1="0" y1="{SY0}" x2="0" y2="{SY1}" gradientUnits="userSpaceOnUse">'
                    f'<stop offset="0" stop-color="{hexc(c0)}"/><stop offset="1" stop-color="{hexc(c1)}"/></linearGradient>')
        fill = f"url(#s{i})"
    else:
        fill = hexc(c)
    print("bande", "bleue" if blue else "or", a, b - 1)
    shapes.append(f'<rect x="{xa}" y="{SY0}" width="{xb - xa}" height="{SY1 - SY0}" fill="{fill}"/>')

# --- croix (vectorielle, déjà au bon format)
cross_svg = subprocess.run(["node", str(here / "cross.js"), *map(str, CROSS), str(W), str(H)],
                           capture_output=True, text=True, check=True).stdout
cross_inner = re.search(r"<svg[^>]*>(.*)</svg>", cross_svg, re.S).group(1)

svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{X0} {Y0} {L} {L}" width="1024" height="1024">
<defs>{"".join(defs)}<clipPath id="frame"><rect x="{X0}" y="{Y0}" width="{L}" height="{L}"/></clipPath></defs>
<g clip-path="url(#frame)">
{"".join(shapes)}
{cross_inner}
<g transform="scale({1 / UP})">
{paths}
</g>
<path d="{text['ribbon']['d']}" fill="{TEXT_COLOR}"/>
<path d="{text['year']['d']}" fill="{YEAR_COLOR}"/>
</g>
</svg>
'''
dest.write_text(svg)
print("chemins vectorisés :", paths.count("<path"), "| taille", round(len(svg) / 1024), "Ko")
