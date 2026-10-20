"""Retrouve la police, la taille et la courbure du texte du blason, et le redessine
en vrai texte vectoriel (lettres converties en tracés), calé sur l'original.

Usage : python3 textfit.py logo.webp out_dir police1.ttf [police2.ttf ...]
Écrit out_dir/text_fit.json (tracés SVG + paramètres retenus).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from fontTools.pens.basePen import BasePen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw

src, out = Path(sys.argv[1]), Path(sys.argv[2])
fonts = sys.argv[3:]
d = np.load(out / "vector_data.npz")
rt, rb = d["rt"], d["ribbon_bottom"]
rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
H, W = rgb.shape[:2]
yy, xx = np.mgrid[0:H, 0:W]
lum = rgb.mean(-1)
dark = np.clip((170 - lum) / 130, 0, 1)

# bas réel de la banderole : on descend depuis l'intérieur jusqu'au premier pixel de champ (bleu ou or)
r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
field = ((r_ > 180) & (b_ < 120) & (g_ > 140)) | ((b_ > 120) & (r_ < 60) & (g_ < 80))
rb = rb.copy()
for x in range(80, 601):
    y = rt[x] + 12
    while y < H - 1 and not field[y, x]:
        y += 1
    rb[x] = y - 1
# masque du texte de la banderole (entre les deux filets) et de « 2020 » (sur la bande or)
band = (yy > rt[None, :] + 8) & (yy < rb[None, :] - 9) & (xx > 85) & (xx < 595)
T_ribbon = dark * band
R_BOX = (85, 180, 595, 310)
yr = (yy > 308) & (yy < 358) & (xx > 270) & (xx < 410)
T_year = dark * yr
Y_BOX = (270, 300, 410, 365)


class PolyPen(BasePen):
    """Aplatit les contours d'un glyphe en polygones."""

    def __init__(self, gs, tf):
        super().__init__(gs)
        self.tf, self.polys, self.cur = tf, [], []

    def _p(self, pt):
        return self.tf(*pt)

    def _moveTo(self, p):
        self.cur = [self._p(p)]

    def _lineTo(self, p):
        self.cur.append(self._p(p))

    def _qCurveToOne(self, p1, p2):
        p0 = self._getCurrentPoint()
        for t in np.linspace(0, 1, 7)[1:]:
            m = 1 - t
            self.cur.append(self._p((m * m * p0[0] + 2 * m * t * p1[0] + t * t * p2[0], m * m * p0[1] + 2 * m * t * p1[1] + t * t * p2[1])))

    def _curveToOne(self, p1, p2, p3):
        p0 = self._getCurrentPoint()
        for t in np.linspace(0, 1, 9)[1:]:
            m = 1 - t
            self.cur.append(self._p(tuple(m**3 * p0[i] + 3 * m * m * t * p1[i] + 3 * m * t * t * p2[i] + t**3 * p3[i] for i in range(2))))

    def _closePath(self):
        if self.cur:
            self.polys.append(self.cur)
        self.cur = []

    _endPath = _closePath


class Font:
    def __init__(self, path):
        self.f = TTFont(path)
        self.gs = self.f.getGlyphSet()
        self.cmap = self.f.getBestCmap()
        self.upm = self.f["head"].unitsPerEm
        self.hmtx = self.f["hmtx"]

    def glyph(self, ch):
        name = self.cmap[ord(ch)]
        return name, self.hmtx[name][0]


def layout(font, text, size, cx, base_mid, R, track, sy=1.0):
    """Matrices (a, b, c, d, e, f) pour chaque glyphe : texte sur un arc de cercle (R=None : droit)."""
    sc = size / font.upm
    items = [font.glyph(c) for c in text]
    advs = [a * sc for _, a in items]
    total = sum(advs) + track * (len(text) - 1)
    s = -total / 2
    mats = []
    for (name, _), adv in zip(items, advs):
        mid = s + adv / 2
        if R:
            phi = mid / R
            px, py = cx + R * math.sin(phi), (base_mid + R) - R * math.cos(phi)
        else:
            phi, px, py = 0.0, cx + mid, base_mid
        c, si = math.cos(phi), math.sin(phi)
        # glyphe : x local = gx*sc - adv/2, y local = -gy*sc ; puis rotation phi et translation
        a, b = c * sc, si * sc
        cc, dd = si * sc * sy, -c * sc * sy
        e = px - c * adv / 2
        f_ = py - si * adv / 2
        mats.append((name, (a, b, cc, dd, e, f_)))
        s += adv + track
    return mats


def render(font, mats, box, ss=3):
    x0, y0, x1, y1 = box
    img = Image.new("L", ((x1 - x0) * ss, (y1 - y0) * ss), 0)
    acc = np.zeros((img.size[1], img.size[0]), bool)
    for name, (a, b, c, dd, e, f_) in mats:
        tf = lambda gx, gy: ((a * gx + c * gy + e - x0) * ss, (b * gx + dd * gy + f_ - y0) * ss)
        pen = PolyPen(font.gs, tf)
        font.gs[name].draw(pen)
        for poly in pen.polys:
            m = Image.new("L", img.size, 0)
            ImageDraw.Draw(m).polygon(poly, fill=255)
            acc ^= np.asarray(m) > 0
    im = Image.fromarray((acc * 255).astype(np.uint8)).resize((x1 - x0, y1 - y0), Image.BOX)
    return np.asarray(im).astype(np.float32) / 255


def loss(font, text, params, target, box):
    m = render(font, layout(font, text, *params), box)
    x0, y0, x1, y1 = box
    t = target[y0:y1, x0:x1]
    return float(((m - t) ** 2).sum())


def fit(font, text, p0, steps, target, box, iters=60):
    p = list(p0)
    best = loss(font, text, p, target, box)
    st = list(steps)
    for _ in range(iters):
        improved = False
        for i in range(len(p)):
            if st[i] == 0:
                continue
            for sgn in (1, -1):
                q = list(p)
                q[i] += sgn * st[i]
                l = loss(font, text, q, target, box)
                if l < best:
                    best, p, improved = l, q, True
                    break
        if not improved:
            st = [s / 2 for s in st]
            if max(st) < 0.02:
                break
    return p, best


results = {}
for fp in fonts:
    font = Font(fp)
    # paramètres : taille, centre x, ligne de base au milieu, rayon de l'arc, interlettrage
    p_r, l_r = fit(font, "AS LA GRINTA", (68, 339.5, 268, 1600, 0, 1.0), (4, 3, 3, 250, 1.5, 0.04), T_ribbon, R_BOX)
    p_y, l_y = fit(font, "2020", (38, 339.5, 346, None, 2, 1.0), (3, 2, 2, 0, 1, 0.04), T_year, Y_BOX)
    results[fp] = dict(ribbon=(l_r, p_r), year=(l_y, p_y))
    print(Path(fp).name, "banderole écart", round(l_r, 1), [round(v, 2) for v in p_r], "| 2020 écart", round(l_y, 1), [round(v, 2) if v is not None else None for v in p_y], flush=True)

# ajustement fin lettre par lettre (décalage et petite rotation), le blason n'étant pas
# parfaitement régulier
def nudge(mat, dx, dy, rot_deg, cx_g, cy_g):
    name, (a, b, c, d_, e, f_) = mat
    th = math.radians(rot_deg)
    co, si = math.cos(th), math.sin(th)
    # rotation autour du centre du glyphe (cx_g, cy_g) puis translation
    A = np.array([[co, -si], [si, co]])
    M = A @ np.array([[a, c], [b, d_]])
    t = A @ (np.array([e, f_]) - [cx_g, cy_g]) + [cx_g, cy_g] + [dx, dy]
    return name, (M[0, 0], M[1, 0], M[0, 1], M[1, 1], t[0], t[1])


def glyph_center(font, mat):
    name, (a, b, c, d_, e, f_) = mat
    adv = font.hmtx[name][0]
    gx, gy = adv / 2, font.upm * 0.36
    return a * gx + c * gy + e, b * gx + d_ * gy + f_


def refine(font, text, params, target, box, rounds=3):
    base = layout(font, text, *params)
    centers = [glyph_center(font, m) for m in base]
    offs = [[0.0, 0.0, 0.0] for _ in base]
    x0, y0, x1, y1 = box
    t = target[y0:y1, x0:x1]
    def L(offs):
        mats = [nudge(m, *o, *c) for m, o, c in zip(base, offs, centers)]
        return float(((render(font, mats, box) - t) ** 2).sum()), mats
    best, mats = L(offs)
    for _ in range(rounds):
        for i, ch in enumerate(text):
            if ch == " ":
                continue
            for k, step in ((0, 1.0), (1, 1.0), (2, 1.0), (0, 0.5), (1, 0.5), (2, 0.5), (0, 0.25), (1, 0.25)):
                for sgn in (1, -1):
                    while True:
                        trial = [list(o) for o in offs]
                        trial[i][k] += sgn * step
                        l, m2 = L(trial)
                        if l < best:
                            best, offs, mats = l, trial, m2
                        else:
                            break
    return best, mats


# meilleure police pour chaque texte, export des tracés SVG
def svg_paths(fp, text, params, target, box):
    font = Font(fp)
    l, mats = refine(font, text, params, target, box)
    print(text, "écart après ajustement lettre par lettre :", round(l, 1), flush=True)
    out_d = []
    for name, m in mats:
        pen = SVGPathPen(font.gs)
        font.gs[name].draw(TransformPen(pen, m))
        out_d.append(pen.getCommands())
    return " ".join(out_d)

best_r = min(results, key=lambda k: results[k]["ribbon"][0])
best_y = min(results, key=lambda k: results[k]["year"][0])
res = {
    "ribbon": {"font": Path(best_r).name, "params": results[best_r]["ribbon"][1], "d": svg_paths(best_r, "AS LA GRINTA", results[best_r]["ribbon"][1], T_ribbon, R_BOX)},
    "year": {"font": Path(best_y).name, "params": results[best_y]["year"][1], "d": svg_paths(best_y, "2020", results[best_y]["year"][1], T_year, Y_BOX)},
}
(out / "text_fit.json").write_text(json.dumps(res))
print("retenu :", res["ribbon"]["font"], "/", res["year"]["font"])
