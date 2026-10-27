"""Where a posed hand's closed fingers make their hole -- the counterpart of the avatar's
grip socket (RS_AVATAR.md 2.5: the centre of the hole the middle, ring and pinky make).
Measured from the hand MESH alone: voxelise the skin, keep the free space outside the
flesh, and score each free voxel by how many directions run into the hand within R cm.
The fist's hole is the biggest connected region of high score; it is a tube, and its
axis is the grip axis."""
import sys, numpy as np
from scipy import ndimage
import gunview, hudrender, ermac

def tri_samples(V, T, step):
    a, b, c = V[T[:, 0]], V[T[:, 1]], V[T[:, 2]]
    L = np.maximum(np.linalg.norm(b - a, axis=1), np.maximum(np.linalg.norm(c - a, axis=1), np.linalg.norm(c - b, axis=1)))
    out = [a, b, c]
    nmax = int(np.ceil(L.max() / step)) + 1
    for n in range(2, nmax + 1):
        sel = np.ceil(L / step) + 1 >= n
        if not sel.any(): break
        for i in range(n + 1):
            for j in range(n + 1 - i):
                u, v = i / n, j / n
                out.append(a[sel] + (b[sel] - a[sel]) * u + (c[sel] - a[sel]) * v)
    return np.concatenate(out)

DIRS = np.array([(i, j, k) for i in (-1, 0, 1) for j in (-1, 0, 1) for k in (-1, 0, 1) if (i, j, k) != (0, 0, 0)]
                + [(2, 1, 0), (1, 2, 0), (2, -1, 0), (1, -2, 0), (2, 0, 1), (1, 0, 2), (2, 0, -1), (1, 0, -2), (0, 2, 1), (0, 1, 2), (0, 2, -1), (0, 1, -2)]
                + [(-2, -1, 0), (-1, -2, 0), (-2, 1, 0), (-1, 2, 0), (-2, 0, -1), (-1, 0, -2), (-2, 0, 1), (-1, 0, 2), (0, -2, -1), (0, -1, -2), (0, -2, 1), (0, -1, 2)], float)

def enclosure(V, T, vox=0.35, R=6.0, pad=1.5):
    P = tri_samples(V, T, vox * 0.45)
    lo = P.min(0) - pad; hi = P.max(0) + pad
    n = np.ceil((hi - lo) / vox).astype(int) + 1
    occ = np.zeros(n, bool)
    ij = np.floor((P - lo) / vox).astype(int)
    occ[ij[:, 0], ij[:, 1], ij[:, 2]] = True
    occ = ndimage.binary_closing(occ, iterations=1) | occ
    lab, nl = ndimage.label(~occ)
    border = set(np.unique(np.concatenate([lab[0].ravel(), lab[-1].ravel(), lab[:, 0].ravel(), lab[:, -1].ravel(), lab[:, :, 0].ravel(), lab[:, :, -1].ravel()])))
    ext = np.isin(lab, [b for b in border if b != 0])
    E = np.zeros(n, float)
    steps = int(R / vox)
    for d in DIRS:
        dn = d / np.linalg.norm(d)
        hit = np.zeros(n, bool)
        for k in range(1, steps + 1):
            o = np.round(dn * k).astype(int)
            sh = np.zeros(n, bool)
            src = tuple(slice(max(0, oi), n[a] + min(0, oi)) for a, oi in enumerate(o))
            dst = tuple(slice(max(0, -oi), n[a] - max(0, oi)) for a, oi in enumerate(o))
            sh[dst] = occ[src]
            hit |= sh
        E += hit
    E /= len(DIRS)
    return dict(lo=lo, vox=vox, occ=occ, ext=ext, E=E)

def hole(V, T, thr=0.86, need=120, **kw):
    """the threshold drops until the hole has `need` voxels: a support hand cradles rather
    than closes, so its hole is shallower than a gun hand's"""
    g = enclosure(V, T, **kw)
    while True:
        m = g['ext'] & (g['E'] >= thr)
        lab, nl = ndimage.label(m)
        sizes = ndimage.sum(m, lab, range(1, nl + 1)) if nl else [0]
        if max(sizes) >= need or thr < 0.55: break
        thr -= 0.02
    big = lab == (1 + int(np.argmax(sizes)))
    idx = np.argwhere(big)
    pts = g['lo'] + (idx + 0.5) * g['vox']
    w = g['E'][big]
    c = pts.mean(0)
    ev, evec = np.linalg.eigh(np.cov((pts - c).T))
    return dict(pts=pts, w=w, centre=c, axis=evec[:, -1], evals=ev, grid=g, thr=round(thr, 2))

def ermac_hand(name, which):
    g, gf, h1, h2, _ = ermac.SETS[name]
    it = dict(path=ermac.E + ('hand/hand.md3' if which == 1 else 'hand/hand2.md3'), frame=h1 if which == 1 else h2, **ermac.PL)
    (tris, raw), = gunview.item_mesh(it)
    return gunview.to_fl(hudrender.to_local(np.asarray(raw, float), it)), tris

def ermac_gun(name):
    g, gf, h1, h2, _ = ermac.SETS[name]
    it = dict(path=ermac.E + g, frame=gf, **ermac.PL)
    V = []; T = []; b = 0
    for tris, raw in gunview.item_mesh(it):
        v = gunview.to_fl(hudrender.to_local(np.asarray(raw, float), it)); V.append(v); T.append(tris + b); b += len(v)
    return np.concatenate(V), np.concatenate(T)
