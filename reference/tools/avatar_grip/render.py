"""Orthographic shaded views of triangle sets in the fit frame (cm, F L U)."""
import math, numpy as np
from PIL import Image, ImageDraw, ImageFont
VIEWS = {  # (h axis, h sign), (v axis, v sign), (depth axis, sign toward viewer)
    'side': ((0, 1), (2, 1), (1, -1)),     # from the gun's right (-L): F right, U up
    'top': ((0, 1), (1, 1), (2, 1)),       # from above: F right, L up
    'front': ((1, -1), (2, 1), (0, 1)),    # from the muzzle: right side to the right
}
LIGHT = np.array([0.3, -0.5, 0.8]); LIGHT /= np.linalg.norm(LIGHT)

def draw(layers, kind, rng, px, W=None, H=None):
    """layers: [(V, T, rgb)] -> PIL image. rng = (h0, h1, v0, v1) cm."""
    (hi, hs), (vi, vs), (di, ds) = VIEWS[kind]
    h0, h1, v0, v1 = rng
    W = W or int((h1 - h0) * px); H = H or int((v1 - v0) * px)
    img = Image.new('RGB', (W, H), (54, 56, 70)); dr = ImageDraw.Draw(img)
    polys = []
    for V, T, col in layers:
        a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
        n = np.cross(b - a, c - a); n /= np.linalg.norm(n, axis=1)[:, None] + 1e-12
        sh = np.abs(n @ LIGHT) * 0.65 + 0.35
        depth = (a[:, di] + b[:, di] + c[:, di]) / 3 * ds
        X = lambda p: (p[:, hi] * hs - h0) * px
        Y = lambda p: H - (p[:, vi] * vs - v0) * px
        xa, ya, xb, yb, xc, yc = X(a), Y(a), X(b), Y(b), X(c), Y(c)
        keep = ~((np.maximum(np.maximum(xa, xb), xc) < 0) | (np.minimum(np.minimum(xa, xb), xc) > W) |
                 (np.maximum(np.maximum(ya, yb), yc) < 0) | (np.minimum(np.minimum(ya, yb), yc) > H))
        colr = (np.array(col)[None, :] * sh[:, None]).astype(int)
        for i in np.nonzero(keep)[0]:
            polys.append((depth[i], ((xa[i], ya[i]), (xb[i], yb[i]), (xc[i], yc[i])), tuple(colr[i])))
    polys.sort(key=lambda t: t[0])
    for _, pts, c in polys:
        dr.polygon(pts, fill=c)
    return img

def to_px(p, kind, rng, px, H):
    (hi, hs), (vi, vs), _ = VIEWS[kind]
    return ((p[hi] * hs - rng[0]) * px, H - (p[vi] * vs - rng[2]) * px)

def grid(img, kind, rng, px, step=5):
    dr = ImageDraw.Draw(img, 'RGBA'); W, H = img.size
    h0, h1, v0, v1 = rng
    for g in range(int(math.floor(h0 / step)) * step, int(h1) + 1, step):
        x = (g - h0) * px; dr.line([(x, 0), (x, H)], fill=(255, 255, 255, 28 if g % 10 else 50))
    for g in range(int(math.floor(v0 / step)) * step, int(v1) + 1, step):
        y = H - (g - v0) * px; dr.line([(0, y), (W, y)], fill=(255, 255, 255, 28 if g % 10 else 50))
